# Right Shortcuts Support

Right Shortcuts adds the actions you choose to Finder's right-click menu. This page covers setup, the questions that come up most, and how to report a problem.

## Set it up

1. Open Right Shortcuts and follow the welcome steps.
2. Turn on the Finder extension. In **Overview**, choose **Turn On…** next to Finder extension. System Settings opens; switch Right Shortcuts on there.
3. Allow file access. Choose **Allow Every Folder…** to cover your whole Mac in one step, or allow single folders. If you skip this, the app asks for a folder the first time an action needs it.
4. Right-click a file or folder in Finder. Your actions are under **Right Shortcuts**.

## Common questions

### The menu doesn't appear

Open Right Shortcuts and look at **Overview**. If the Finder extension is off, choose **Turn On…**. If it is on and the menu is still missing, switch it off and on again in System Settings, then check **Folders** ▸ **Where the menu appears**.

### The menu is missing only on the Desktop or in Documents

Those folders are probably stored in iCloud Drive. Finder doesn't ask any extension for menu items inside iCloud Drive or other cloud-synced folders, and no app of this kind can change that. The menu works in every other folder.

The only way to get it on the Desktop and in Documents is to turn off **Desktop & Documents Folders** in your iCloud Drive settings. That changes where those files are kept, so read what macOS tells you before you confirm.

### An action says it has no permission

The app can work only in folders you allowed. Open **Folders** ▸ **Where Right Shortcuts can work** and choose **Allow a Folder…** or **Allow Every Folder…**. A folder on a drive that is unplugged is marked “not connected” and works again once you plug the drive in.

### A custom command doesn't run

Custom commands need a small helper script that only you can install. Open **General** and choose **Install Helper…**, then confirm in the window that opens. **Show Helper in Finder** shows the script; it is plain text, so you can read exactly what it does.

### A copy is taking a long time

Large copies show a progress bar with a **Stop** button. Stopping leaves nothing half-copied behind, and an existing file is never replaced.

### How do I change what is in the menu?

Open **Menu Items**. Turn items on or off, drag to reorder, and choose **Edit…** to rename an item, change its icon or pick where it shows. **New File** holds the file templates.

### How do I stop it opening at login?

Open **General** and turn off **Open at login**.

## Remove the app and its data

Quit Right Shortcuts and move it from Applications to the Trash. Your settings stay behind. To remove them too, open Finder, choose **Go ▸ Go to Folder…**, type `~/Library` and delete these:

- in **Containers**: the two folders that Finder shows as “Right Shortcuts”;
- in **Group Containers**: the folder whose name ends in `com.georgekhananaev.RightShortcuts`;
- in **Application Scripts**: the two folders whose names start with `com.georgekhananaev.RightShortcuts`.

## Report a problem

Open an issue at [github.com/georgekhananaev/right-shortcuts/issues](https://github.com/georgekhananaev/right-shortcuts/issues) and include:

- your macOS version and the app version shown in **About**;
- what you did, what you expected and what happened instead.

**General ▸ Export Diagnostics…** saves a text file that helps a lot. Read it before attaching it: issues are public, and the file can contain file and folder names.

## Privacy

Right Shortcuts collects nothing. See the [privacy policy](PRIVACY.md).
