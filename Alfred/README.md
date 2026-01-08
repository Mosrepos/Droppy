# Droppy Alfred Workflow

Quickly add files to Droppy from Finder using Alfred file actions.

## Installation

1. Double-click `Droppy.alfredworkflow` to install
2. Ensure Droppy v4.9+ is running

## Usage

1. Select files in Finder
2. Activate Alfred (⌘ + Space)
3. Type "Actions" or use your file action hotkey
4. Choose:
   - **Add to Droppy Shelf** → Sends files to the notch shelf
   - **Add to Droppy Basket** → Sends files to the floating basket

## Requirements

- Droppy v4.9+ (with URL scheme support)
- Alfred 4+ with Powerpack

## URL Scheme

The workflow uses Droppy's URL scheme:

```
droppy://add?target=shelf&path=/path/to/file
droppy://add?target=basket&path=/path/to/file1&path=/path/to/file2
```

You can use this URL scheme from other apps or scripts too!
