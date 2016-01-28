def create_demo_data(model_name, yaml_attributes, find_key_name)
  model_klass = model_name.constantize
  model_obj = model_klass.find_or_initialize_by "#{find_key_name}": yaml_attributes[find_key_name]
  model_obj.destroy if model_obj.persisted?
  print "Creating #{model_name} #{yaml_attributes[find_key_name]}..."
  model_obj = model_klass.new
  model_obj.attributes = yaml_attributes

  # モデル固有のフィールド設定をブロック呼び出し
  yield(model_obj) if block_given?

  begin
    model_obj.save!
    puts 'SUCCESS!'
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
            # recordは配列となっており、record[1]=yamlデータ上の識別子、record[2]=yaml化されたattributesで構成されている
            # そのため、実際に登録したいデータのattributesを、record.lastとして参照している
            yaml_attributes = record.last

            # モデル名毎にでもデータを登録する
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

            when "Member"
              user_login = yaml_attributes.delete('user_login')
              user = User.find_by login: user_login
              project_identifier = yaml_attributes.delete('project_identifier')
              project = Project.find_by identifier: project_identifier

              print "Adding #{user.login} to --> #{project.name}..."
              member = Member.new(project: project, user_id: user.id)
              admin = User.active.find_by(login: "admin") || User.active.where(admin: true).first
              member.set_editable_role_ids(Role.givable.pluck(:id).collect {|e| e.to_s}, admin)
              begin
                member.save!
                puts 'SUCCESS!'
              rescue => e
                puts "FAILD! because -> #{e.message}"
              end

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
