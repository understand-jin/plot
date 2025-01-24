extensions [py csv]

globals [
  contract
  year-demand-std
  primary-order-quantity
  ;option-order-quantity
  ;safety-stock
  service-level-primary
  service-level-option
  procurement-volume
  std
  disruption-probability
  dual-mean
  dual-std
  disruption-mean
  disruption-std
  primary-supply-quantity
  ss-position
  total-reservation-quantity
  is-disrupted ; 현재 disruption 여부
  disruption-schedule ; disruption이 발생할 주기 리스트
  recovery-timer ; 회복까지 남은 주기
  now-disruption-frequency
  ;procurement-quantity
  next-disruption-timer
  target-ticks
  common-demand
  ;holding-cost
  shortage-cost-now
  shortage-amount
  csv-filename
  procurable-amount
  real-procurement
  service-level-inventory
]

breed [players player]

players-own [
  role
  id-number
  pen-color
  inventory-position
  cost
  revenue
  profit
]

directed-link-breed [supply-links supply-link]
supply-links-own [pair-demand-link orders-filled lead-time]

directed-link-breed [demand-links demand-link]
demand-links-own [orders-placed]

to setup
  clear-all
  set target-ticks (episode * 52)
  ;random-seed 12345
  random-seed (disruption-frequency * 100 + recovery * 100)
  setup-python
  setup-csv
  layout
  initialize
  calculate
  set holding-cost (yearly-holding-cost / 52)
  ;set holding-cost 1
  set contract 0
  set is-disrupted false
  set next-disruption-timer round random-exponential (52 / disruption-frequency)
  show (word "next-disruption-timer : " next-disruption-timer )
  reset-ticks
end

to setup-csv
  ; 동적으로 파일 이름 생성
  set csv-filename (word "Data_" Version "_" disruption-frequency "_" recovery "_"coefficient-of-variation "_w" ordering-cost-of-primary-supplier ".csv")
  ;set csv-filename (word "manufacturer_data_" Version "_" disruption-frequency "_" recovery ".csv")
  ;set csv-filename (word "Fixed_" Version "_" disruption-frequency "_" recovery "_"coefficient-of-variation".csv")
  ;set csv-filename (word "Safety-stock_" Version "_" disruption-frequency "_" recovery "_"coefficient-of-variation "_" safety-stock ".csv")
  ;set csv-filename (word "Option-reservation_" Version "_" disruption-frequency "_" recovery "_"coefficient-of-variation "_" option-order-quantity ".csv")

  ; CSV 파일 생성 및 헤더 추가
  file-close-all
  file-open csv-filename
  let header-row ["ticks" "inventory-position" "ss-position" "cost" "revenue" "profit" "shortage-cost-now" "shortage-amount" "common-demand" "disruption" "total-reservation-quantity"]
  csv:to-file csv-filename (list header-row)
  file-close
end

to setup-python
  py:setup py:python
  py:run "from inverse_function import set_seed, generate_common_demand, calculate, variability_inventory, variability_dual, monte_carlo_inventory_strategy, monte_carlo_dual_sourcing"
  py:run "set_seed(12345)"  ; 시드를 설정하여 버전별로 동일한 시퀀스를 보장
end



to layout
  set-default-shape players "default"
  set-default-shape links "default"

  create-players 1 [
    set id-number 0
    setxy -8 8
    set color yellow
    set role "primary-supplier"
    set size 6
    set shape "house two story"
    set label "primary-supplier"
    set pen-color 0
  ]

  create-players 1 [
    set id-number 1
    setxy -8 -6
    set color yellow
    set role "dual-sourcing-supplier"
    set size 6
    set shape "house ranch"
    set label "dual-sourcing-supplier"
    set pen-color 50
  ]

  create-players 1 [
    set id-number 2
    setxy 8 1
    set color green
    set role "manufacturer"
    set size 8
    set shape "house colonial"
    set label "manufacturer"
    set pen-color 100
  ]

  ask players with[role = "manufacturer"] [
    create-demand-links-to players with [id-number = 0 or id-number = 1]
    create-supply-links-from players with [id-number = 0 or id-number = 1]
  ]

  ask supply-links [
    set pair-demand-link one-of demand-links with [
      (end1 = [end2] of myself and end2 = [end1] of myself)
    ]
    set orders-filled []
  ]

end

to initialize
  ask players [
    if role = "manufacturer" [
      set inventory-position 0
      set ss-position 0
    ]
  ]
  set contract 0
end

to go
  ;show " ----------------------------------------"
  ;show (word " ticks : " ticks)
  let now ticks mod 52
  ;show(word " ticks mod 52 : " now)
  primary-supplier-contract
  dual-supplier-contract
  demand
  manage-disruptions
  procurement
  replenish-safety-stock
  generate-demand
  calculate-holding-cost
  calculate-total-profit
  save-manufacturer-data
  tick
end

to keep-going
  while [ticks < target-ticks] [
    go
  ]
  show "Simulation complete!"
end

to calculate
  set std (year-demand-mean * coefficient-of-variation)
  show(word"std : " std)
  set service-level-primary (price-of-product - ordering-cost-of-primary-supplier) / (price-of-product - salvage-value)
  show(word"service-level-primary : " service-level-primary)
  py:set "mean" year-demand-mean
  py:set "std_dev" std
  py:set "service_level" service-level-primary
  set primary-order-quantity int py:runresult "calculate(mean, std_dev, service_level)"
  show(word"primary-order-quantity : " primary-order-quantity)
  set procurable-amount round (primary-order-quantity / 52)
  show(word " procurable-amount : " procurable-amount)

  set service-level-option (price-of-product - reservation-cost - exercise-cost) / (price-of-product - exercise-cost)
  show(word"service-level-option : " service-level-option)
  let real-recovery (52 / ((52 / recovery) + 0.5))
  ;show (word" real-recovery : " real-recovery)
  set disruption-probability (disruption-frequency / (disruption-frequency + real-recovery))
  ;show(word " disruption-probability : " disruption-probability)
  set dual-mean (year-demand-mean * disruption-probability)
  ;show(word "dual-mean : " dual-mean)
  set dual-std (std * disruption-probability)
  ;show(word "dusl-std : " dual-std)
  py:set "mean" dual-mean
  py:set "std_dev" dual-std
  py:set "service_level" service-level-option
  py:set "week_mean" (year-demand-mean / 52)
  py:set "week_std" ((year-demand-mean / 52) * coefficient-of-variation)
  py:set "lead_time_mean" ((52 / recovery) + 0.5)
  py:set "lead_time_std" ((52 / recovery) + 0.5)
  py:set "mu_x" (year-demand-mean / 52)
  py:set "sigma_x" ((year-demand-mean / 52) * coefficient-of-variation)
  py:set "recoveryy" (52 / recovery)
  ;show((52 / recovery))
  py:set "disruption_frequency" disruption-frequency
  py:set "num_simulations" 100000
  py:set "disruption_frequency" disruption-frequency
  py:set "recovery" recovery
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ;set option-order-quantity int py:runresult "variability_dual(week_mean, week_std, service_level, lead_time_mean, lead_time_std, disruption_frequency, recovery)"
  ;set option-order-quantity int py:runresult "calculate(mean, std_dev, service_level)"
  set option-order-quantity int py:runresult "monte_carlo_dual_sourcing(mu_x, sigma_x, disruption_frequency, recoveryy, num_simulations, service_level)"
  ;set option-order-quantity option-order-quantity
  show(word"option-order-quantity : " option-order-quantity)

  let recovery-period (1 / real-recovery)
  ;show(word " recovery-period : " recovery-period)
  set disruption-mean (year-demand-mean * recovery-period)
  ;show(word "disruption-mean : " disruption-mean)
  set disruption-std (std * recovery-period)
  ;show(word " disruption-std : " disruption-std)
  set service-level-inventory ((price-of-product - ordering-cost-of-primary-supplier)*((disruption-frequency * recovery) / (disruption-frequency + recovery)) - yearly-holding-cost) / ((price-of-product - ordering-cost-of-primary-supplier)*((disruption-frequency * recovery) / (disruption-frequency + recovery)))
    show(word " service-level-inventory : " service-level-inventory)
  py:set "mean" disruption-mean
  py:set "std_dev" disruption-std
  py:set "service_level" service-level-inventory
  py:set "week_mean" (year-demand-mean / 52)
  py:set "week_std" ((year-demand-mean / 52) * coefficient-of-variation)
  py:set "lead_time_mean" ((52 / recovery) + 0.5)
  py:set "lead_time_std" ((52 / recovery) + 0.5)
  py:set "mu_x" (year-demand-mean / 52)
  py:set "sigma_x" ((year-demand-mean / 52) * coefficient-of-variation)
  py:set "mu_y" (52 / recovery)
  py:set "num_simulations" 100000
  ;set safety-stock int py:runresult "variability_inventory(week_mean, week_std, service_level, lead_time_mean, lead_time_std)"
  ;set safety-stock  int py:runresult "calculate(mean, std_dev, service_level)"
  set safety-stock int py:runresult "monte_carlo_inventory_strategy(mu_x, sigma_x, mu_y, num_simulations, service_level)"
  ;set safety-stock safety-stock
  show(word"safety-stock : " safety-stock)
end

to primary-supplier-contract
  if ticks = 0 or ticks = contract + 52  [
    ask players with [role = "manufacturer"] [
      let primary-supplier one-of players with [role = "primary-supplier"]
      ask primary-supplier [
        set primary-supply-quantity primary-order-quantity
        ;show(word "primary-supply-quantity : " primary-supply-quantity)
      ]
      set cost cost + (primary-order-quantity * ordering-cost-of-primary-supplier)

      if Version = "inventory-strategy" [
        if ss-position < safety-stock [
          ;show(word " before ss : " ss-position)
          let difference (safety-stock - ss-position)
          set ss-position (ss-position + difference)
          ;show(word "after ss : " ss-position)
          set cost cost + (difference * ordering-cost-of-primary-supplier)
        ]
      ]
    ]
  ]
end

to dual-supplier-contract
  if ticks = 0 or ticks = contract + 52 [
    if Version = "Dual-sourcing" [
      ask players with [role = "manufacturer"][
        let dual-supplier one-of players with [role = "dual-sourcing-supplier"]
        ask dual-supplier [
           set total-reservation-quantity option-order-quantity
          ;show (word " total reservation-quantity : " total-reservation-quantity)
         ]
        set cost cost + (option-order-quantity * reservation-cost)
      ]
    ]
    set contract ticks
  ]
end

to manage-disruptions
  ifelse is-disrupted [
    ; 회복 중인 경우
    ifelse recovery-timer > 0 [
      set recovery-timer recovery-timer - 1
    ] [
      ; 회복 완료
      set is-disrupted false
      let next-disruption-period random-exponential (52 / disruption-frequency )
      set next-disruption-timer round (next-disruption-period + 0.5)
      show (word "next-disruption-timer : " next-disruption-timer )
      ;show "Disruption ended. System recovered."
    ]
  ] [
    ; 장애가 발생하지 않은 경우
    ifelse next-disruption-timer > 0 [
      set next-disruption-timer next-disruption-timer - 1
    ] [
      ; 장애 발생
      set is-disrupted true
      ;random-seed (disruption-frequency * 100 + recovery * 100)
      let recover-period random-exponential (52 / recovery)
      set recovery-timer round (recover-period + 0.5)  ; 평균 2주 회복 시간 설정
      if recovery-timer = 0 [
        set recovery-timer 1
      ]
      show (word "Disruption occurred! Recovery time: " recovery-timer " weeks.")
      set recovery-timer (recovery-timer - 1)
    ]
  ]
end

to procurement
  ifelse not is-disrupted [
    ; 정상 조달: primary-supplier로부터 매주 조달
    ask players with [role = "manufacturer"] [
      set real-procurement min list common-demand procurable-amount
      let primary-supplier one-of players with [role = "primary-supplier"]

      ask primary-supplier [
        set primary-supply-quantity primary-supply-quantity - procurable-amount
        ;show (word "primary-supply-quantity : " primary-supply-quantity)
      ]

      set inventory-position inventory-position + real-procurement
      ;show (word "inventory-position : " inventory-position)
    ]

  ] [
    ; is-disrupted 상태
    ask players with [role = "manufacturer"] [
      let primary-supplier one-of players with [role = "primary-supplier"]

      ; 장애 상태에서도 primary-supply-quantity 감소
      ask primary-supplier [
        set primary-supply-quantity primary-supply-quantity - procurable-amount
        ;show (word "primary-supply-quantity (disrupted): " primary-supply-quantity)
      ]
    ]

    if Version = "Dual-sourcing" [
      ; Dual-sourcing일 때 dual-sourcing-supplier로부터 자원 조달
      ask players with [role = "manufacturer"] [
        let dual-supplier one-of players with [role = "dual-sourcing-supplier"]
        let available-quantity min list total-reservation-quantity common-demand

        ask dual-supplier [
          set total-reservation-quantity total-reservation-quantity - available-quantity
          ;show (word "total-reservation-quantity after procurement: " total-reservation-quantity)
        ]

        set inventory-position inventory-position + available-quantity
        ;show (word "Updated inventory-position: " inventory-position)

        set cost cost + (available-quantity * exercise-cost)
      ]
    ]
  ]
end


to calculate-holding-cost
  ask players with [role = "manufacturer"] [
    ;show(word " before calculate-holding-cost : " inventory-position)
  set cost cost + ((inventory-position + ss-position) * holding-cost)
  ;show (word "Total cost: " cost)
  ]
end

to replenish-safety-stock
  if Version = "inventory-strategy" and not is-disrupted [
    if ss-position < safety-stock [
      ask players with [role = "manufacturer"] [
        let primary-supplier one-of players with [role = "primary-supplier"]

        let required-quantity safety-stock - ss-position
        set ss-position ss-position + required-quantity

        let replenishment-cost required-quantity * ordering-cost-of-primary-supplier
        set cost cost + replenishment-cost

        ;show (word "Replenished ss-position by: " required-quantity)
        ;show (word "Updated ss-position: " ss-position)
      ]
    ]
  ]
end

to demand
  ;show(word " mean :" (year-demand-mean / 52) ", " "std : " ((year-demand-mean / 52) * coefficient-of-variation))
  py:set "mean" (year-demand-mean / 52)
  py:set "std_dev" ((year-demand-mean / 52) * coefficient-of-variation)
  set common-demand py:runresult "generate_common_demand(mean, std_dev)"
  ;show (word "Generated common demand: " common-demand)
end


to generate-demand
  set shortage-amount 0

  ask players with [role = "manufacturer"] [
    if Version = "Dual-sourcing" [
      let procurementable-amount max list 0 (min list inventory-position common-demand)
      set revenue revenue + (price-of-product * procurementable-amount)
      set inventory-position inventory-position - procurementable-amount
      ;show (word " after demand inventory-position : " inventory-position)
      let remaining-demand (common-demand - procurementable-amount)


      if remaining-demand > 0 [
        set shortage-amount remaining-demand
        set shortage-cost-now (shortage-amount * shortage-cost)
        set cost cost + shortage-cost-now
        ;show (word "Warning: shortage occurred. Shortage cost: " shortage-cost-now)
        ;set inventory-position 0  ; 재고 부족한 경우 0으로 설정
      ]
    ]

    if Version = "inventory-strategy" [
      ; inventory-strategy 버전
      let allocated-from-inventory max list 0 (min list common-demand inventory-position)
      set revenue revenue + (price-of-product * allocated-from-inventory)
      set inventory-position inventory-position - allocated-from-inventory
      let remaining-demand common-demand - allocated-from-inventory

      if is-disrupted [
      let allocated-from-ss max list 0 (min list remaining-demand ss-position)
      ;show (word "allocated-from-ss : " allocated-from-ss)
      set revenue revenue + (price-of-product * allocated-from-ss)
      set ss-position ss-position - allocated-from-ss
      ;show( word "ss-position : " ss-position)
      set remaining-demand remaining-demand - allocated-from-ss
      ]

      ; 부족 시 비용 추가
      if remaining-demand > 0 [
        set shortage-amount remaining-demand
        ;show(word " shortage-amount : " shortage-amount)
        set shortage-cost-now remaining-demand * shortage-cost
        set cost cost + shortage-cost-now
        ;show (word "Warning: shortage occurred. Shortage cost: " shortage-cost-now)
      ]

      ;show (word "Generated demand: " common-demand " | Updated inventory-position: " inventory-position " | Updated ss-position: " ss-position)
    ]
    if Version = "Wholesale" [
      let procurementable-amount max list 0 (min list inventory-position common-demand)
      ;show(word "procurementable-amount : " procurementable-amount)
      set revenue revenue + (price-of-product * procurementable-amount)
      set inventory-position inventory-position - procurementable-amount
      ;show (word " after demand inventory-position : " inventory-position)
      let remaining-demand (common-demand - procurementable-amount)


      if remaining-demand > 0 [
        set shortage-amount remaining-demand
        ;show(word "shortge-amount : " shortage-amount)
        set shortage-cost-now (shortage-amount * shortage-cost)
        set cost cost + shortage-cost-now
        ;show (word "Warning: shortage occurred. Shortage cost: " shortage-cost-now)
        ;set inventory-position 0  ; 재고 부족한 경우 0으로 설정
      ]
    ]
    ;show(word "reveneue : " revenue)
    ;show(word "shortage-amount : " shortage-amount)
  ]
end

to calculate-total-profit
  ask players with [role = "manufacturer"] [
    set profit (revenue - cost)
    ;show (word " profit : " profit)
  ]
end

to-report mean-normal [avg stddev]
  let result 0
  while [result <= 0] [ ;true일 때 반복함.
    set result round (random-normal avg stddev)
  ]
  report result
end

to save-manufacturer-data
  let reservation-quantity 0
  ask players with [role = "dual-sourcing-supplier"] [
    set reservation-quantity total-reservation-quantity
  ]

  ask players with [role = "manufacturer"] [
    let data-row (word ticks "," inventory-position "," ss-position "," cost "," revenue "," profit "," shortage-cost-now "," shortage-amount "," common-demand "," is-disrupted "," reservation-quantity)

    ; 데이터를 파일에 추가
    file-open csv-filename
    file-print data-row
    file-close
  ]
end
@#$#@#$#@
GRAPHICS-WINDOW
177
69
714
607
-1
-1
16.03030303030303
1
10
1
1
1
0
1
1
1
-16
16
-16
16
0
0
1
ticks
30.0

BUTTON
47
79
113
112
NIL
setup\n
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SLIDER
734
102
915
135
disruption-frequency
disruption-frequency
0
100
6.0
1
1
NIL
HORIZONTAL

SLIDER
737
147
909
180
recovery
recovery
0
200
52.0
1
1
NIL
HORIZONTAL

CHOOSER
183
17
347
62
Version
Version
"Dual-sourcing" "inventory-strategy" "Wholesale"
2

BUTTON
49
124
112
157
NIL
go
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

TEXTBOX
742
78
892
96
Disruption
15
0.0
1

TEXTBOX
743
211
893
229
Demand\t\t\t\t
15
0.0
1

SLIDER
735
234
928
267
year-demand-mean
year-demand-mean
0
10000
5200.0
100
1
NIL
HORIZONTAL

SLIDER
742
376
1006
409
ordering-cost-of-primary-supplier
ordering-cost-of-primary-supplier
0
1000
20.0
10
1
NIL
HORIZONTAL

SLIDER
744
414
916
447
reservation-cost
reservation-cost
0
100
5.0
1
1
NIL
HORIZONTAL

SLIDER
742
455
914
488
exercise-cost
exercise-cost
0
500
30.0
1
1
NIL
HORIZONTAL

SLIDER
744
495
916
528
price-of-product
price-of-product
0
1000
50.0
1
1
NIL
HORIZONTAL

TEXTBOX
749
346
899
364
Cost setting
15
0.0
1

SLIDER
736
275
930
308
coefficient-of-variation
coefficient-of-variation
0
1
0.1
0.1
1
NIL
HORIZONTAL

SLIDER
743
534
915
567
option-fixed-cost
option-fixed-cost
0
100
0.0
1
1
NIL
HORIZONTAL

SLIDER
744
573
916
606
salvage-value
salvage-value
0
100
0.0
1
1
NIL
HORIZONTAL

SLIDER
956
101
1128
134
episode
episode
0
10000
200.0
1
1
NIL
HORIZONTAL

TEXTBOX
971
78
1121
112
Simulation episode\n\n
15
0.0
1

SLIDER
744
611
916
644
shortage-cost
shortage-cost
0
100
0.0
1
1
NIL
HORIZONTAL

BUTTON
33
170
135
203
NIL
keep-going
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SLIDER
745
652
917
685
safety-stock
safety-stock
0
10000
300.0
100
1
NIL
HORIZONTAL

SLIDER
747
695
919
728
holding-cost
holding-cost
0
100
0.09615384615384616
0.1
1
NIL
HORIZONTAL

SLIDER
949
412
1135
445
option-order-quantity
option-order-quantity
0
10000
999.0
100
1
NIL
HORIZONTAL

SLIDER
747
740
922
773
yearly-holding-cost
yearly-holding-cost
0
100
5.0
1
1
NIL
HORIZONTAL

@#$#@#$#@
## WHAT IS IT?

(a general understanding of what the model is trying to show or explain)

## HOW IT WORKS

(what rules the agents use to create the overall behavior of the model)

## HOW TO USE IT

(how to use the model, including a description of each of the items in the Interface tab)

## THINGS TO NOTICE

(suggested things for the user to notice while running the model)

## THINGS TO TRY

(suggested things for the user to try to do (move sliders, switches, etc.) with the model)

## EXTENDING THE MODEL

(suggested things to add or change in the Code tab to make the model more complicated, detailed, accurate, etc.)

## NETLOGO FEATURES

(interesting or unusual features of NetLogo that the model uses, particularly in the Code tab; or where workarounds were needed for missing features)

## RELATED MODELS

(models in the NetLogo Models Library and elsewhere which are of related interest)

## CREDITS AND REFERENCES

(a reference to the model's URL on the web if it has one, as well as any other necessary credits, citations, and links)
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

building institution
false
0
Rectangle -7500403 true true 0 60 300 270
Rectangle -16777216 true false 130 196 168 256
Rectangle -16777216 false false 0 255 300 270
Polygon -7500403 true true 0 60 150 15 300 60
Polygon -16777216 false false 0 60 150 15 300 60
Circle -1 true false 135 26 30
Circle -16777216 false false 135 25 30
Rectangle -16777216 false false 0 60 300 75
Rectangle -16777216 false false 218 75 255 90
Rectangle -16777216 false false 218 240 255 255
Rectangle -16777216 false false 224 90 249 240
Rectangle -16777216 false false 45 75 82 90
Rectangle -16777216 false false 45 240 82 255
Rectangle -16777216 false false 51 90 76 240
Rectangle -16777216 false false 90 240 127 255
Rectangle -16777216 false false 90 75 127 90
Rectangle -16777216 false false 96 90 121 240
Rectangle -16777216 false false 179 90 204 240
Rectangle -16777216 false false 173 75 210 90
Rectangle -16777216 false false 173 240 210 255
Rectangle -16777216 false false 269 90 294 240
Rectangle -16777216 false false 263 75 300 90
Rectangle -16777216 false false 263 240 300 255
Rectangle -16777216 false false 0 240 37 255
Rectangle -16777216 false false 6 90 31 240
Rectangle -16777216 false false 0 75 37 90
Line -16777216 false 112 260 184 260
Line -16777216 false 105 265 196 265

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

house colonial
false
0
Rectangle -7500403 true true 270 75 285 255
Rectangle -7500403 true true 45 135 270 255
Rectangle -16777216 true false 124 195 187 256
Rectangle -16777216 true false 60 195 105 240
Rectangle -16777216 true false 60 150 105 180
Rectangle -16777216 true false 210 150 255 180
Line -16777216 false 270 135 270 255
Polygon -7500403 true true 30 135 285 135 240 90 75 90
Line -16777216 false 30 135 285 135
Line -16777216 false 255 105 285 135
Line -7500403 true 154 195 154 255
Rectangle -16777216 true false 210 195 255 240
Rectangle -16777216 true false 135 150 180 180

house ranch
false
0
Rectangle -7500403 true true 270 120 285 255
Rectangle -7500403 true true 15 180 270 255
Polygon -7500403 true true 0 180 300 180 240 135 60 135 0 180
Rectangle -16777216 true false 120 195 180 255
Line -7500403 true 150 195 150 255
Rectangle -16777216 true false 45 195 105 240
Rectangle -16777216 true false 195 195 255 240
Line -7500403 true 75 195 75 240
Line -7500403 true 225 195 225 240
Line -16777216 false 270 180 270 255
Line -16777216 false 0 180 300 180

house two story
false
0
Polygon -7500403 true true 2 180 227 180 152 150 32 150
Rectangle -7500403 true true 270 75 285 255
Rectangle -7500403 true true 75 135 270 255
Rectangle -16777216 true false 124 195 187 256
Rectangle -16777216 true false 210 195 255 240
Rectangle -16777216 true false 90 150 135 180
Rectangle -16777216 true false 210 150 255 180
Line -16777216 false 270 135 270 255
Rectangle -7500403 true true 15 180 75 255
Polygon -7500403 true true 60 135 285 135 240 90 105 90
Line -16777216 false 75 135 75 180
Rectangle -16777216 true false 30 195 93 240
Line -16777216 false 60 135 285 135
Line -16777216 false 255 105 285 135
Line -16777216 false 0 180 75 180
Line -7500403 true 60 195 60 240
Line -7500403 true 154 195 154 255

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.4.0
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
<experiments>
  <experiment name="SensitivityAnalysis" repetitions="1" sequentialRunOrder="false" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>keep-going</go>
    <steppedValueSet variable="disruption-frequency" first="1" step="1" last="12"/>
  </experiment>
</experiments>
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
0
@#$#@#$#@
