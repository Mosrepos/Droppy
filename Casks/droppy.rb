cask "droppy" do
  version "2.0.3"
  sha256 "82d4a3ecb0332cb2dbb06dd3b0b5f08baabbfc51cd57c87eddb271e3098ebec9"

  url "https://raw.githubusercontent.com/iordv/Droppy/main/Droppy-2.0.3.dmg"
  name "Droppy"
  desc "Drag and drop file shelf for macOS"
  homepage "https://github.com/iordv/Droppy"

  app "Droppy.app"

  zap trash: [
    "~/Library/Application Support/Droppy",
    "~/Library/Preferences/iordv.Droppy.plist",
  ]
end
