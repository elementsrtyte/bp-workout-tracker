import UIKit

/// Aligns UIKit-backed controls (search bars, form accessories, cursors, steppers) with `BlueprintTheme`
/// so the app does not flash default iOS blue.
enum BlueprintUIKitAccents {
    static func apply() {
        let purple = UIColor(red: 0.482, green: 0.369, blue: 0.655, alpha: 1)
        let lavender = UIColor(red: 0.769, green: 0.588, blue: 1.0, alpha: 1)

        UITextField.appearance().tintColor = lavender
        UITextView.appearance().tintColor = lavender
        UITextField.appearance(whenContainedInInstancesOf: [UISearchBar.self]).tintColor = lavender

        UISearchBar.appearance().tintColor = purple

        UINavigationBar.appearance().tintColor = purple
        UITableView.appearance().tintColor = purple

        UISwitch.appearance().onTintColor = purple
        UIStepper.appearance().tintColor = lavender
        UIDatePicker.appearance().tintColor = lavender
    }
}
