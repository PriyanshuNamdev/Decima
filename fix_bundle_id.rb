require 'xcodeproj'
require 'securerandom'

project_path = 'Gallery-Organiser.xcodeproj'
project = Xcodeproj::Project.open(project_path)

unique_id = SecureRandom.hex(4)
new_bundle_id = "com.gallerycleaner.app#{unique_id}"

project.targets.each do |target|
  target.build_configurations.each do |config|
    config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = new_bundle_id
    puts "Set bundle ID to #{new_bundle_id}"
  end
end

project.save
puts "Successfully forced new bundle identifiers."
