cask "droppy" do
  version "11.3"
  sha256 "101d859d1d7a3bf082caa42b5d15a952b36bce41888c834faf623721e718f8c0"

  url "https://github.com/iordv/Droppy/releases/download/v11.3/Droppy-11.3.dmg"
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
