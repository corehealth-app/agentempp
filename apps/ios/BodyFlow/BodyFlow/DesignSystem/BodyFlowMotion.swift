enum BodyFlowMotion {
    static func duration(reduceMotion: Bool, disclosure: Bool) -> Double {
        reduceMotion ? 0 : (disclosure ? 0.25 : 0.20)
    }
}
