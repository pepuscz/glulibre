/// default alert levels to be used when creating defalt alert entries
enum ConstantsDefaultAlertLevels {
    // default battery alert level, below this level an alert should be generated - this default value will be used when changing transmittertype
    static let defaultBatteryAlertLevelDexcomG5 = 270
    static let defaultBatteryAlertLevelMiaoMiao = 20
    static let defaultBatteryAlertLevelBubble = 20
    static let defaultBatteryAlertLevelLibre2 = 20
    static let defaultBatteryAlertLevelPhone = 10
    
    // New schedules only; existing persisted personal schedules are never overwritten.
    // Libre's published low/high defaults are 70/240 mg/dL. The ADA level-2
    // hypoglycemia boundary is 54 mg/dL. These are safety thresholds, not food scores.
    // Sources and applicability: docs/NOTIFICATIONS_4233.md.
    static let veryHigh = 250
    static let veryLow = 54
    static let high = 240
    static let low = 70
    
    // blood glucose fast drop delta alert in mgdl
    static let fastdrop = 10
    static let fastdropTriggerValue = 120

    // blood glucose fast rise delta alert in mgdl
    static let fastrise = 10
    static let fastriseTriggerValue = 160
    
    // in minutes, after how many minutes of now reading should alert be raised
    static let missedReading = 30
    
    // in hours, after how many hours alert to request a new calibration
    static let calibration = 24
}
