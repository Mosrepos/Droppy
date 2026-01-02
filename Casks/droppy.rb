cask "droppy" do
  version "1.2.2"
  sha256 "daebd927d55d72f221cd6dbecbf2e7fdb2f66bccc1ddfc348e707a03f529218c"

  url "https://raw.githubusercontent.com/iordv/Droppy/main/Droppy.dmg"
  name "Droppy"
  desc "Drag and drop file shelf for macOS"
  homepage "https://github.com/iordv/Droppy"

  app "Droppy.app"

  zap trash: [
    "~/Library/Application Support/Droppy",
    "~/Library/Preferences/iordv.Droppy.plist",
  ]
end
