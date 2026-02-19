cask "droppy" do
  version "11.2.1"
  sha256 "ced02dc9341bb304c7da56eca3c1011ffb8720929c1523836b3e7e76a38fa84c"

  url "https://github.com/iordv/Droppy/releases/download/v11.2.1/Droppy-11.2.1.dmg"
  name "Droppy"
  desc "Drag and drop file shelf for macOS"
  homepage "https://github.com/iordv/Droppy"

  auto_updates true

  app "Droppy.app"

  postflight do
    system_command "/usr/bin/xattr",
      args: ["-d", "com.apple.quarantine", "#{appdir}/Droppy.app"],
      must_succeed: false,
      sudo: false
  end

  caveats <<~EOS
    ____                             
   / __ \_________  ____  ____  __  __
  / / / / ___/ __ \/ __ \/ __ \/ / / /
 / /_/ / /  / /_/ / /_/ / /_/ / /_/ / 
/_____/_/   \____/ .___/ .___/\__, /  
                /_/   /_/    /____/   

    Thank you for installing Droppy! 
    The ultimate drag-and-drop file shelf for macOS.
  EOS

  zap trash: [
    "~/Library/Application Support/Droppy",
    "~/Library/Preferences/iordv.Droppy.plist",
  ]
end
