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
      filename = Dir[File.join(Rails.root, 'plugins', 'redmine_demo_project', 'db', 'demo_data.yml')][0]
      File.open(filename, 'r') do |file|
        YAML::load(file).each do |yaml|
          yaml.last.each do |table_name, records|
            model_name = table_name.singularize.camelize
            model_klass = model_name.constantize
            records.each do |record|
              case model_name
              when "User"
                model_obj = model_klass.find_or_initialize_by login: record.first
                model_obj.destroy if model_obj.persisted?
                print "Create #{model_name} #{record.first}..."
                model_obj = model_klass.new
                model_obj.login = record.first
                model_obj.attributes = record.last
                model_obj.admin = false
                model_obj.register
                model_obj.activate
                begin
                  model_obj.save!
                  puts 'CREATED!'
                rescue => e
                  puts "FAILD! because -> #{e.message}"
                end
              when "Project"
                model_obj = model_klass.find_or_initialize_by identifier: record.first
                model_obj.destroy if model_obj.persisted?
                print "Create #{model_name} #{record.first}..."
                model_obj = model_klass.new
                model_obj.attributes = record.last
                begin
                  model_obj.save!
                  puts 'CREATED!'
                rescue => e
                  puts "FAILD! because -> #{e.message}"
                end
              end
            end
          end
=begin
          user = User.find_or_initialize_by login: record.first
          binding.pry
          unless user.persisted?
            print "Create User #{user_attributes[:login]}..."
            binding.pry
            user.attributes = record.attributes
            user.admin = false
            user.register
            user.activate
            begin
              user.save!
              puts 'SAVED!'
            rescue => e
              puts "FAILD! because -> #{e.message}"
            end
          else
            puts "User #{record.first} exist."
          end
=end
        end
      end
    end
  end
end
