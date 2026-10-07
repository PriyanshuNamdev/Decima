require 'xcodeproj'
project_path = 'Gallery-Organiser.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.first

# Add files from folders recursively
def add_files_to_group(project, target, group, path)
  Dir.foreach(path) do |entry|
    next if entry == '.' or entry == '..' or entry == '.DS_Store'
    full_path = File.join(path, entry)
    if File.directory?(full_path)
      # Check if group exists, if not create
      subgroup = group.children.find { |c| c.name == entry && c.class == Xcodeproj::Project::Object::PBXGroup }
      subgroup = group.new_group(entry, entry) unless subgroup
      add_files_to_group(project, target, subgroup, full_path)
    elsif entry.end_with?('.swift')
      # check if already added
      unless group.children.any? { |c| c.name == entry && c.class == Xcodeproj::Project::Object::PBXFileReference }
        file_ref = group.new_file(entry)
        target.add_file_references([file_ref])
        puts "Added #{full_path}"
      end
    end
  end
end

main_group = project.main_group.children.find { |c| c.name == 'Gallery-Organiser' }
unless main_group
    main_group = project.main_group.children.find { |c| c.path == 'Gallery-Organiser' }
end

add_files_to_group(project, target, main_group, 'Gallery-Organiser')
project.save
puts "Project saved successfully."
