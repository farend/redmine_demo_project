def create_demo_data(model_name, yaml_attributes, find_key_name)
  model_klass = model_name.constantize
  if find_key_name
    model_obj = model_klass.find_or_initialize_by "#{find_key_name}": yaml_attributes[find_key_name]
  else
    model_obj = model_klass.new
  end
  model_obj.destroy if model_obj.persisted?
  print "Creating #{model_name} #{yaml_attributes[find_key_name]}..."
  model_obj = model_klass.new
  model_obj.attributes = yaml_attributes

  # モデル固有のフィールド設定をブロック呼び出し
  yield(model_obj) if block_given?

  begin
    model_obj.save!
    puts 'SUCCESS!'
    return model_obj
  rescue => e
    puts "FAILD! because -> #{e.message}"
    return nil
  end
end

namespace :redmine do
  namespace :demo_project do
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
              create_demo_data(model_name, yaml_attributes, 'login') do |user|
                user.login = yaml_attributes['login']
                user.admin = false
                user.register
                user.activate
              end

            when "Tracker"
              Tracker.skip_callback(:destroy, :before, :check_integrity)
              copy_workflow_from_name = yaml_attributes.delete('copy_workflow_from_name')
              tracker = create_demo_data(model_name, yaml_attributes, 'name') do |tracker|
                tracker.default_status_id = IssueStatus.first.id
              end
              copy_workflow_from = Tracker.find_by name: copy_workflow_from_name
              tracker.workflow_rules.copy(copy_workflow_from)

            when "Project"
              tracker_names = yaml_attributes.delete('tracker_names')
              create_demo_data(model_name, yaml_attributes, 'identifier') do |project|
                trackers = Tracker.where('name IN (?)', tracker_names)
                project.trackers = trackers
              end

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
              create_demo_data(model_name, yaml_attributes, 'name') do |version|
                project = Project.find_by identifier: project_identifier
                version.project = project
              end

            when "Issue"
              project_identifier = yaml_attributes.delete('project_identifier')
              assigned_user_login = yaml_attributes.delete('assigned_user_login')
              fixed_version_name = yaml_attributes.delete('fixed_version_name')
              issue_status_name = yaml_attributes.delete('status_name')
              tracker_name = yaml_attributes.delete('tracker_name')
              create_demo_data(model_name, yaml_attributes, 'subject') do |issue|
                project = Project.find_by identifier: project_identifier
                assigned_user = User.find_by login: assigned_user_login
                fixed_version = Version.find_by name: fixed_version_name
                issue_status = IssueStatus.find_by name: issue_status_name
                tracker = Tracker.find_by name: tracker_name
                issue.project = project
                issue.author = assigned_user
                issue.assigned_to = assigned_user
                issue.fixed_version = fixed_version
                issue.status = issue_status
                #issue.tracker ||= issue.project.trackers.first
                issue.tracker = tracker
              end
            end
          end
        end
      end
    end
  end
end
