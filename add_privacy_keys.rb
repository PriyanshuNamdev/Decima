require 'xcodeproj'

project_path = 'Gallery-Organiser.xcodeproj'
project = Xcodeproj::Project.open(project_path)

project.targets.each do |target|
  target.build_configurations.each do |config|
    config.build_settings['INFOPLIST_KEY_NSPhotoLibraryUsageDescription'] = '"Gallery Cleaner needs access to your photos to identify duplicates and large videos."'
    puts "Added NSPhotoLibraryUsageDescription to #{target.name} - #{config.name}"
  end
end

project.save
puts "Successfully added privacy keys."
