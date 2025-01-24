import scipy.stats as stats
import random
import math 
import numpy as np

def calculate(mean, std_dev, service_level):
    try:
        result = stats.norm.ppf(service_level, loc=mean, scale=std_dev)
    except Exception as e:
        print(f"Error in calculating quantile: {e}")
        result = None
    return result

#stats.norm: 정규 분포
#ppf : CDF(누적분포함수)의 역함수 

# 초기 시드를 고정하는 함수
# def set_seed(seed_value):
#     random.seed(seed_value)

# # def generate_common_demand(mean, std_dev):
# #     return int(abs(random.normalvariate(mean, std_dev)))
# # random.normalvariate() 는 정규 분포에 따르는 난수 생성 
# def generate_common_demand(mean, std_dev):
#     # 0 이상 200 이하의 값이 나올 때까지 반복 생성
#     while True:
#         demand = int(abs(random.normalvariate(mean, std_dev)))
#         if 0 <= demand <= 200:
#             return demand

def set_seed(seed_value):
    """시드를 설정하고 난수 상태를 초기화"""
    global random_state
    random.seed(seed_value)
    random_state = random.getstate()

def generate_common_demand(mean, std_dev):
    """지정된 평균(mean)과 표준편차(std_dev)로 정규 분포에 따르는 수요 생성"""
    global random_state
    # 이전 난수 상태 복원
    random.setstate(random_state)
    # 난수 생성
    while True:
        demand = int(abs(random.normalvariate(mean, std_dev)))
        if 0 <= demand <= 200:
            break
    # 현재 난수 상태 저장
    random_state = random.getstate()
    return demand

#먼저 파이썬에서 시드를 생성함. -> 동일한 시드 값이 주어질 때마다 항상 동일한 난수 시퀀스가 생성 
# Netlogo와 Python을 연동하여 시뮬레이션의 시작 시에만 시드를 고정하고, 이후 매 틱마다 Python에서 난수를 생성하여 가져옴 

def variability(week_mean, week_std, service_level, lead_time_mean, lead_time_std):
    z = stats.norm.ppf(service_level)
    quantity = (week_mean * lead_time_mean + z * math.sqrt((lead_time_mean**2) * (week_std **2) + (week_mean ** 2) * (lead_time_std ** 2)))
    return quantity

def variability_inventory(week_mean, week_std, service_level, lead_time_mean, lead_time_std):
    z = stats.norm.ppf(service_level)
    #print(z)
    quantity = (week_mean * lead_time_mean + z * math.sqrt((lead_time_mean**2) * (week_std **2) + (week_mean ** 2) * (lead_time_std ** 2) + (week_std ** 2) * (lead_time_std ** 2)))
    return quantity

def variability_dual(week_mean, week_std, service_level, lead_time_mean, lead_time_std, disruption_frquency, recovery):
    z = stats.norm.ppf(service_level)
    num_of_disruption = (disruption_frquency * recovery) / (disruption_frquency + recovery)
    #print(num_of_disruption)
    quantity = (num_of_disruption * week_mean * lead_time_mean + z * math.sqrt((num_of_disruption ** 2) * ((lead_time_mean**2) * (week_std **2) + (week_mean ** 2) * (lead_time_std ** 2) + (week_std ** 2) * (lead_time_std ** 2))))
    return quantity

# 몬테카를로 시뮬 (inventory 버전)
def monte_carlo_inventory_strategy(mu_x, sigma_x, mu_y, num_simulations, service_level):
    all_sums = []
    #print(mu_x, sigma_x, mu_y, num_simulations, service_level)

    for _ in range(num_simulations):
        n_samples = round((np.random.exponential(mu_y)) + 0.5)
        samples = np.random.normal(mu_x, sigma_x, n_samples)
        all_sums.append(np.sum(samples))

    # Sort the cumulative sums
    all_sums = np.sort(all_sums)

    # Calculate the quantile value for the service level
    quantile_index = int(len(all_sums) * service_level) - 1
    quantile_value = all_sums[quantile_index]

    return quantile_value

#몬테카를로 시뮬(dual 버전)
# def monte_carlo_dual_sourcing(mu_x, sigma_x, mu_y, mu_z, num_simulations, service_level):
#     total_down_demands = []
#     #print(mu_x, sigma_x, mu_y, mu_z, num_simulations, service_level)
#     for _ in range(num_simulations):
#         recovery_time = int(round((np.random.exponential(mu_y))))

#         disruption_frequency = int(np.random.exponential(mu_z))

#         total_disruption_time = disruption_frequency * recovery_time

#         demands = np.random.normal(mu_x, sigma_x, total_disruption_time)
#         total_down_demand = np.sum(demands)

#         total_down_demands.append(total_down_demand)

#     sorted_demands = np.sort(total_down_demands)
#     quantile_index = int(len(sorted_demands) * service_level) - 1
#     quantile_value = sorted_demands[quantile_index]

#     return quantile_value

class DisruptionSimulation: 
    def __init__(self, disruption_frequency, recovery, simulation_steps):
        self.disruption_frequency = disruption_frequency
        self.recovery = recovery
        self.simulation_steps = simulation_steps
        self.is_disrupted = False
        self.recovery_timer = 0
        self.next_disruption_timer = self.generate_next_disruption()
        self.down_weeks = 0 

    def generate_next_disruption(self):
        return int(np.round(np.random.exponential(52 / self.disruption_frequency)))
    
    def generate_recovery_time(self):
        recovery_period = np.random.exponential(self.recovery)
        return max(1, int(np.round(recovery_period + 0.5)))
    
    def step(self):
        if self.is_disrupted:
            self. down_weeks += 1
            if self.recovery_timer >= 1: 
                self.recovery_timer -= 1
            if self.recovery_timer == 0 :
                self.is_disrupted = False
                self.next_disruption_timer = self.generate_next_disruption()

        else: 
            if self.next_disruption_timer >= 1:
                self.next_disruption_timer -= 1
            if self.next_disruption_timer == 0:
                self.is_disrupted = True
                self.recovery_timer = self.generate_recovery_time()

    def run_simulation(self):
        #history = []
        for step in range(self.simulation_steps):
            # history.append({
            #     'step' : step,
            #     'is_disrupted' : self.is_disrupted,
            #     'recovery_timer' : self.recovery_timer,
            #     'next_disruption_timer' : self.next_disruption_timer
            # })
            #print(history)
            self.step()
        return self.down_weeks

def monte_carlo_dual_sourcing(mu_x, sigma_x, disruption_frequency, recovery, num_simulations, service_level):
    print(f"disruption_fequency : {disruption_frequency}")
    print(f"recovery : {recovery}")
    total_down_demands = []

    for _ in range(num_simulations):
        sim = DisruptionSimulation(disruption_frequency, recovery, 52)  
        total_disruption_time = sim.run_simulation() 

        demands = np.random.normal(mu_x, sigma_x, total_disruption_time)

        total_down_demand = np.sum(demands)
        total_down_demands.append(total_down_demand)

    sorted_demands = np.sort(total_down_demands)
    quantile_index = int(len(sorted_demands) * service_level) - 1
    quantile_value = sorted_demands[max(0, min(quantile_index, len(sorted_demands) - 1))]

    return quantile_value

# def monte_carlo_dual_sourcing(mu_x, sigma_x, mu_y, mu_z, num_simulations, service_level):
#     total_down_demands = []
#     #print(mu_x, sigma_x, mu_y, mu_z, num_simulations, service_level)
#     for _ in range(num_simulations):

#         disruption_frequency = int(np.random.exponential(mu_z))

#         recovery_times = [int(round((np.random.exponential(mu_y)) + 0.5)) for _ in range(disruption_frequency)]

#         total_disruption_time = sum(recovery_times)

#         demands = np.random.normal(mu_x, sigma_x, total_disruption_time)

#         total_down_demand = np.sum(demands)

#         total_down_demands.append(total_down_demand)

#     sorted_demands = np.sort(total_down_demands)
#     quantile_index = int(len(sorted_demands) * service_level) - 1
#     quantile_value = sorted_demands[quantile_index]

#     return quantile_value