// the git panel.
// mostly a clone of atom's git panel, with a few small changes
// discarding changes shouldn't clear your commit message
// the push button is in the panel instead of on the bottom bar
// the commit list should have a way to scroll and diff any old commit but maybe not
// this one probably will have less features because git is complicated
// definitely must have:
// - visible list of past commits, clear undo option for most recent
// - visibly seperate "unstaged" and "staged" boxes (unlike vscode)
// - commit message box with visible "commit" button

pub fn init() void {}
pub fn deinit() void {}
pub fn render() void {}

/// for saving and reloading workspaces
pub fn serialize() void {}
pub fn deserialize() void {}
