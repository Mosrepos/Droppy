cask "droppy" do
  version "11.1.4"
  sha256 "e49db20b36a00891f35f8515ede4928ebc12d33dd4e1f34a672a74007fe4b46b"

  url "https://github.com/iordv/Droppy/releases/download/v11.1.4/Droppy-11.1.4.dmg"
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
