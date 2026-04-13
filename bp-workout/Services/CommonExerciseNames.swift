import Foundation

/// Static catalog of common gym exercise names for program editor autocomplete (not exhaustive).
/// The editor always accepts any typed name; this list only powers optional suggestions.
enum CommonExerciseNames {
    private static let rawNames: String = """
    Ab Wheel Rollout
    Air Bike
    Arnold Press
    Assault Bike
    Back Extension
    Ball Slam
    Barbell Back Squat
    Barbell Bench Press
    Barbell Curl
    Barbell Deadlift
    Barbell Front Squat
    Barbell Hip Thrust
    Barbell Row
    Barbell Shrug
    Battle Ropes
    Bench Dip
    Bicycle Crunch
    Bent-Over Barbell Row
    Block Pull
    Bodyweight Squat
    Box Jump
    Box Squat
    Bulgarian Split Squat
    Burpee
    Butterfly (Pec Deck)
    Cable Chest Fly
    Cable Crunch
    Cable Crossover
    Cable Curl
    Cable Face Pull
    Cable Kickback
    Cable Lat Pulldown
    Cable Lateral Raise
    Cable Pullover
    Cable Row
    Cable Tricep Pushdown
    Cable Wood Chop
    Calf Press on Leg Press
    Calf Raise (Seated)
    Calf Raise (Standing)
    Captain's Chair Knee Raise
    Chest Dip
    Chest Fly (Dumbbell)
    Chest Press Machine
    Chest-Supported Row
    Chin-Up
    Clean and Jerk
    Clamshell
    Close-Grip Bench Press
    Concentration Curl
    Copenhagen Plank
    Crossover Step-Up
    Crunch
    Curtsy Lunge
    Dead Bug
    Decline Bench Press
    Decline Push-Up
    Deficit Deadlift
    Diamond Push-Up
    Dip (Assisted)
    Dip (Parallel Bars)
    Donkey Calf Raise
    Dragon Flag
    Dumbbell Arnold Press
    Dumbbell Bench Press
    Dumbbell Bent-Over Row
    Dumbbell Bulgarian Split Squat
    Dumbbell Clean
    Dumbbell Curl
    Dumbbell Deadlift
    Dumbbell Fly
    Dumbbell Front Raise
    Dumbbell Goblet Squat
    Dumbbell Hammer Curl
    Dumbbell Incline Curl
    Dumbbell Incline Press
    Dumbbell Lateral Raise
    Dumbbell Lunge
    Dumbbell Overhead Press
    Dumbbell Pullover
    Dumbbell Reverse Fly
    Dumbbell Romanian Deadlift
    Dumbbell Row
    Dumbbell Shoulder Press
    Dumbbell Shrug
    Dumbbell Snatch
    Dumbbell Step-Up
    Dumbbell Tricep Kickback
    Dumbbell Upright Row
    Elliptical
    Face Pull
    Farmer's Carry
    Farmer's Walk
    Flat Bench Cable Fly
    Floor Press
    Flutter Kicks
    Front Plank
    Front Raise
    Front Squat
    Glute Bridge
    Glute-Ham Raise
    Goblet Squat
    Good Morning
    Hack Squat
    Hammer Curl
    Handstand Push-Up
    Hang Clean
    Hanging Knee Raise
    Hanging Leg Raise
    High Pull
    Hip Abduction Machine
    Hip Adduction Machine
    Hip Thrust
    Hollow Body Hold
    Hyperextension
    Incline Barbell Bench Press
    Incline Cable Fly
    Incline Dumbbell Press
    Incline Skull Crusher
    Inverted Row
    Iso-Lateral Row
    Jackknife Sit-Up
    Jefferson Curl
    JM Press
    Jump Rope
    Jump Squat
    Jumping Jack
    Kettlebell Goblet Squat
    Kettlebell Swing
    Kettlebell Turkish Get-Up
    Kneeling Cable Crunch
    Landmine Press
    Landmine Row
    Landmine Squat
    Lat Pulldown (Close Grip)
    Lat Pulldown (Reverse Grip)
    Lat Pulldown (Wide Grip)
    Lateral Raise
    Leg Curl (Lying)
    Leg Curl (Seated)
    Leg Extension
    Leg Press
    Leg Raise
    Lying Leg Curl
    Lying Leg Raise
    Lying Tricep Extension
    Machine Chest Press
    Machine Dip
    Machine Row
    Machine Shoulder Press
    Medicine Ball Slam
    Military Press (Standing)
    Mountain Climber
    Neutral-Grip Pull-Up
    Nordic Hamstring Curl
    Overhead Cable Extension
    Overhead Dumbbell Extension
    Overhead Press
    Overhead Squat
    Pallof Press
    Pec Deck Fly
    Pendlay Row
    Pin Press
    Pistol Squat
    Plank
    Power Clean
    Preacher Curl
    Prowler Push
    Pull-Up
    Push Press
    Push-Up
    Rack Pull
    Rear Delt Fly (Dumbbell)
    Renegade Row
    Reverse Cable Fly
    Reverse Crunch
    Reverse Hyperextension
    Reverse Lunge
    Romanian Deadlift
    Rope Cable Curl
    Rope Tricep Pushdown
    Russian Twist
    Scaption Raise
    Scott Curl
    Scissor Kicks
    Seated Cable Row
    Seated Calf Raise
    Seated Dumbbell Press
    Seated Leg Curl
    Seated Row Machine
    Shoulder Press Machine
    Side Plank
    Single-Arm Cable Row
    Single-Arm Dumbbell Row
    Single-Leg Deadlift
    Sissy Squat
    Skull Crusher
    Sled Push
    Smith Machine Bench Press
    Smith Machine Squat
    Spider Curl
    Split Squat
    Squat Jump
    Squat to Box
    Stair Climber
    Standing Calf Raise
    Star Jump
    Stiff-Leg Deadlift
    Straight-Arm Pulldown
    Sumo Deadlift
    Superhero Plank
    Superman
    T-Bar Row
    Tempo Squat
    Thruster
    Toes to Bar
    Trap Bar Deadlift
    Tricep Bench Dip
    Tricep Dip
    Tricep Overhead Extension (Dumbbell)
    Turkish Get-Up
    Upright Row
    V-Bar Pulldown
    V-Up
    Waiter's Walk
    Walking Lunge
    Wall Ball
    Wall Sit
    Wide-Grip Pull-Up
    Wood Chop
    Wrist Curl
    Yates Row
    Zottman Curl
    """

    /// Alphabetically sorted, deduplicated catalog.
    static let all: [String] = {
        let parsed = rawNames
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let unique = Array(Set(parsed))
        return unique.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }()

    /// Prefix matches first, then substring matches; capped for UI.
    static func suggestions(matching query: String, limit: Int = 12) -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let q = trimmed.lowercased()
        let prefixMatches = all.filter { $0.lowercased().hasPrefix(q) }
        if prefixMatches.count >= limit {
            return Array(prefixMatches.prefix(limit))
        }
        let prefixSet = Set(prefixMatches)
        let substringMatches = all.filter { name in
            !prefixSet.contains(name) && name.lowercased().contains(q)
        }
        return prefixMatches + Array(substringMatches.prefix(limit - prefixMatches.count))
    }
}
