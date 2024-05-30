import SwiftUI
import HealthKit

struct ContentView: View {
    @State private var selectedDate = Date()
    @State private var stepCount: Double = 0
    @State private var hoursSlept: Double = 0
    @State private var heartRate: Double = 0
    @State private var hrv: Double = 0
    @State private var healthStore = HKHealthStore()
    
    var body: some View {
        VStack {
            DatePicker("Select Date", selection: $selectedDate, displayedComponents: .date)
                .padding()
            
            Text("Step Count: \(stepCount, specifier: "%.0f")")
            Text("Hours Slept: \(hoursSlept, specifier: "%.1f")")
            Text("Heart Rate: \(heartRate, specifier: "%.1f")")
            Text("HRV: \(hrv, specifier: "%.2f")")
            
            Button(action: writeData) {
                Text("Write Data")
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            
            Button(action: fetchData) {
                Text("Fetch Data")
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
        }
        .onAppear(perform: requestAuthorization)
        .padding()
    }
    
    private func requestAuthorization() {
        let typesToShare: Set = [
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!
        ]
        
        let typesToRead: Set = [
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!
        ]
        
        healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead) { (success, error) in
            if !success {
                print("Authorization failed")
            }
        }
    }
    
    private func writeData() {
        let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        let stepQuantity = HKQuantity(unit: HKUnit.count(), doubleValue: 10000)
        let stepSample = HKQuantitySample(type: stepType, quantity: stepQuantity, start: selectedDate, end: selectedDate)
        
        let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)!
        let sleepSample = HKCategorySample(type: sleepType, value: HKCategoryValueSleepAnalysis.asleep.rawValue, start: selectedDate, end: selectedDate.addingTimeInterval(8 * 60 * 60))
        
        let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        let heartRateQuantity = HKQuantity(unit: HKUnit(from: "count/min"), doubleValue: 70)
        let heartRateSample = HKQuantitySample(type: heartRateType, quantity: heartRateQuantity, start: selectedDate, end: selectedDate)
        
        let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!
        let hrvQuantity = HKQuantity(unit: HKUnit.secondUnit(with: .milli), doubleValue: 50)
        let hrvSample = HKQuantitySample(type: hrvType, quantity: hrvQuantity, start: selectedDate, end: selectedDate)
        
        healthStore.save([stepSample, sleepSample, heartRateSample, hrvSample]) { (success, error) in
            if success {
                print("Data written successfully")
            } else {
                print("Error writing data: \(error?.localizedDescription ?? "Unknown error")")
            }
        }
    }
    
    private func fetchData() {
        fetchSteps { (steps) in
            DispatchQueue.main.async {
                self.stepCount = steps
            }
        }
        
        fetchSleep { (hours) in
            DispatchQueue.main.async {
                self.hoursSlept = hours
            }
        }
        
        fetchHeartRate { (rate) in
            DispatchQueue.main.async {
                self.heartRate = rate
            }
        }
        
        fetchHRV { (hrv) in
            DispatchQueue.main.async {
                self.hrv = hrv
            }
        }
    }
    
    private func fetchSteps(completion: @escaping (Double) -> Void) {
        let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        let predicate = HKQuery.predicateForSamples(withStart: selectedDate, end: selectedDate.addingTimeInterval(24 * 60 * 60), options: .strictStartDate)
        
        let query = HKStatisticsQuery(quantityType: stepType, quantitySamplePredicate: predicate, options: .cumulativeSum) { (_, result, error) in
            var steps: Double = 0
            
            if let result = result, let sum = result.sumQuantity() {
                steps = sum.doubleValue(for: HKUnit.count())
            }
            
            completion(steps)
        }
        
        healthStore.execute(query)
    }
    
    private func fetchSleep(completion: @escaping (Double) -> Void) {
        let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)!
        let predicate = HKQuery.predicateForSamples(withStart: selectedDate, end: selectedDate.addingTimeInterval(24 * 60 * 60), options: .strictStartDate)
        
        let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { (_, results, error) in
            var totalSleep: Double = 0
            
            if let results = results {
                for result in results {
                    if let sample = result as? HKCategorySample {
                        if sample.value == HKCategoryValueSleepAnalysis.asleep.rawValue {
                            totalSleep += sample.endDate.timeIntervalSince(sample.startDate)
                        }
                    }
                }
            }
            
            completion(totalSleep / 3600) // Convert seconds to hours
        }
        
        healthStore.execute(query)
    }
    
    private func fetchHeartRate(completion: @escaping (Double) -> Void) {
        let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        let predicate = HKQuery.predicateForSamples(withStart: selectedDate, end: selectedDate.addingTimeInterval(24 * 60 * 60), options: .strictStartDate)
        
        let query = HKSampleQuery(sampleType: heartRateType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { (_, results, error) in
            var totalHeartRate: Double = 0
            var count: Double = 0
            
            if let results = results {
                for result in results {
                    if let sample = result as? HKQuantitySample {
                        totalHeartRate += sample.quantity.doubleValue(for: HKUnit(from: "count/min"))
                        count += 1
                    }
                }
            }
            
            completion(count > 0 ? totalHeartRate / count : 0)
        }
        
        healthStore.execute(query)
    }
    
    private func fetchHRV(completion: @escaping (Double) -> Void) {
        let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!
        let predicate = HKQuery.predicateForSamples(withStart: selectedDate, end: selectedDate.addingTimeInterval(24 * 60 * 60), options: .strictStartDate)
        
        let query = HKSampleQuery(sampleType: hrvType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { (_, results, error) in
            var totalHRV: Double = 0
            var count: Double = 0
            
            if let results = results {
                for result in results {
                    if let sample = result as? HKQuantitySample {
                        totalHRV += sample.quantity.doubleValue(for: HKUnit.secondUnit(with: .milli))
                        count += 1
                    }
                }
            }
            
            completion(count > 0 ? totalHRV / count : 0)
        }
        
        healthStore.execute(query)
    }
}
