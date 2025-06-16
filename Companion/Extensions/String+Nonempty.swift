extension Swift.String {
    var nonempty: String? {
        guard !isEmpty else { return nil }
        return self
    }
}
