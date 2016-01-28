def create_demo_data(model_name, yaml_attributes, find_key_name)
  model_klass = model_name.constantize
  model_obj = model_klass.find_or_initialize_by "#{find_key_name}": yaml_attributes[find_key_name]
  model_obj.destroy if model_obj.persisted?
  print "Create #{model_name} #{yaml_attributes[find_key_name]}..."
  model_obj = model_klass.new
  model_obj.attributes = yaml_attributes
  yield(model_obj) if block_given?
  begin
    model_obj.save!
    puts 'CREATED!'
  rescue => e
    puts "FAILD! because -> #{e.message}"
  end
end

namespace :redmine do
  namespace :demo_project do
    #desc 'Load Redmine Demo-data using seed file'
    #task :load_from_seed => :environment do |t|
    #  filename = Dir[File.join(Rails.root, 'plugins', 'redmine_demo_project', 'db', 'demodata_seeds.rb')][0]
    #  puts "Seeding Demo-data #{filename}..."
    #  load(filename) if File.exist?(filename)
    #end
    
    desc 'Load Redmine Demo-data using yaml file'
    task :load_from_yaml => :environment do |t|
      yaml_file_path = Dir[File.join(Rails.root, 'plugins', 'redmine_demo_project', 'db', 'demo_data.yml')][0]
      YAML::load(ERB.new(File.read(yaml_file_path)).result).each do |yaml|
        yaml.last.each do |table_name, records|
          model_name = table_name.singularize.camelize
          records.each do |record|
            yaml_attributes = record.last
            case model_name
            when "User"
              create_demo_data(model_name, yaml_attributes, 'login') do |model_obj|
                model_obj.login = yaml_attributes['login']
                model_obj.admin = false
                model_obj.register
                model_obj.activate
              end
            when "Project"
              create_demo_data(model_name, yaml_attributes, 'identifier')
            when "Version"
              project_identifier = yaml_attributes.delete('project_identifier')
              create_demo_data(model_name, yaml_attributes, 'name') do |model_obj|
                project = Project.find_by identifier: project_identifier
                model_obj.project = project
              end
            end
          end
        end
      end
    end
  end
end
