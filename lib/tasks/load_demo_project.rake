def create_demo_data(model_name, yaml_attributes, find_keys, validate = true)
  model_klass = model_name.constantize
  find_keys = Array.wrap(find_keys)
  if find_keys.any?
    #model_obj = model_klass.find_or_initialize_by "#{find_key_name}": yaml_attributes[find_key_name]
    model_obj = model_klass.find_or_initialize_by Hash[*find_keys.collect{|key|[key, yaml_attributes[key]]}.flatten]
  else
    model_obj = model_klass.new
  end
  model_obj.destroy if model_obj.persisted?
  print "Creating #{model_name} #{find_keys.collect{|key|yaml_attributes[key]}.to_s}..."
  model_obj = model_klass.new
  model_obj.attributes = yaml_attributes

  # モデル固有のフィールド設定をブロック呼び出し
  yield(model_obj) if block_given?

  begin
    model_obj.save!(validate: validate)
    puts 'SUCCESS!'
    return model_obj
  rescue => e
    puts "FAILD! : #{e.message}"
    raise e
  end
end

namespace :redmine do
  namespace :demo_project do
    desc 'Load Redmine Demo-data using yaml file'
    task :load => :environment do |t|
      ActiveRecord::Base.transaction do
        demo_data_file_path = Dir[File.join(Rails.root, 'plugins', 'redmine_demo_project', 'db', 'demo_data.yml')][0]
        YAML::load(ERB.new(File.read(demo_data_file_path)).result).each do |yaml|
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
                  user.password = yaml_attributes['password']
                  user.password_confirmation = yaml_attributes['password_confirmation']
                  user.admin = false
                  user.generate_password = 0
                  user.must_change_passwd = 0
                  user.register
                  user.activate
                end
  
              when "Tracker"
                Tracker.skip_callback(:destroy, :before, :check_integrity)
                tracker = create_demo_data(model_name, yaml_attributes, 'name') do |tracker|
                  tracker.default_status_id = IssueStatus.first.id
                end
                # トラッカーにワークフローを設定する
                print "Updating Tracker #{tracker.name}...."
                roles = Role.all
                # YAMLで定義されたワークフローのtransitionsをロードしてHashに変換する
                transitions_file_path = Dir[File.join(Rails.root, 'plugins', 'redmine_demo_project', 'db', 'transitions.yml')][0]
                transitions = YAML::load(ERB.new(File.read(transitions_file_path)).result).to_h
                # YAMLからロードしたワークフローの設定をトラッカーにセットする
                begin
                  WorkflowTransition.replace_transitions(tracker, roles, transitions)
                  puts 'SUCCESS!'
                rescue => e
                  puts "FAILD! : #{e.message}"
                  raise e
                end
  
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
  
                print "Adding Member #{user.login} to --> #{project.name}..."
                member = Member.new(project: project, user_id: user.id)
                admin = User.active.find_by(login: "admin") || User.active.where(admin: true).first
                member.set_editable_role_ids(Role.givable.pluck(:id).collect {|e| e.to_s}, admin)
                begin
                  member.save!
                  puts 'SUCCESS!'
                rescue => e
                  puts "FAILD! : #{e.message}"
                  raise e
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
                assigned_user = User.find_by login: assigned_user_login
                fixed_version_name = yaml_attributes.delete('fixed_version_name')
                issue_status_name = yaml_attributes.delete('status_name')
                tracker_name = yaml_attributes.delete('tracker_name')
                start_date = yaml_attributes.delete('start_date')
                end_date = yaml_attributes.delete('end_date')
                issue = create_demo_data(model_name, yaml_attributes, ['subject', 'fixed_version_id'], false) do |issue|
                  project = Project.find_by identifier: project_identifier
                  fixed_version = Version.find_by name: fixed_version_name
                  # issue_status = IssueStatus.find_by name: issue_status_name
                  issue_status = IssueStatus.find_by name: '新規'
                  tracker = Tracker.find_by name: tracker_name
                  issue.project = project
                  issue.author = assigned_user
                  issue.assigned_to = assigned_user
                  issue.fixed_version = fixed_version
                  issue.status = issue_status
                  #issue.tracker ||= issue.project.trackers.first
                  issue.tracker = tracker
                end
                issue_status = IssueStatus.find_by name: issue_status_name
                
                if issue_status_name == "進行中" || issue_status_name == "終了"
                  print "Updating Issue #{issue.subject} status -> 進行中..."
                  issue.init_journal(assigned_user, '作業に着手しました。')
                  journal = issue.current_journal
                  journal.created_on = start_date
                  issue_status = IssueStatus.find_by name: '進行中'
                  issue.status = issue_status
                  issue.start_date = start_date
                  issue.done_ratio = rand(1..8) * 10 # 進捗率 = 10% 〜 80%
                  begin
                    issue.save!(validate: false)
                    puts 'SUCCESS!'
                  rescue => e
                    puts "FAILD! : #{e.message}"
                    raise e
                  end
                end

                if issue_status_name == "終了"
                  print "Updating Issue #{issue.subject} status -> 終了..."
                  # issue.reload  # MEMO: issue.reloadだと進行中で設定したjournalが上書きされるので、もう一度findする
                  issue = Issue.find(issue.id)
                  issue.init_journal(assigned_user, '作業が完了しました。')
                  journal = issue.current_journal
                  journal.created_on = end_date if end_date.present?
                  issue_status = IssueStatus.find_by name: '終了'
                  issue.status = issue_status
                  # :issue.update_done_ratio_from_issue_status
                  issue.done_ratio = 100 # 進捗率 = 100%
                  begin
                    issue.save!(validate: false)
                    puts 'SUCCESS!'
                  rescue => e
                    puts "FAILD! : #{e.message}"
                    raise e
                  end
                end

              end # end of case model_name
            end # end of records.each
          end # end of yaml.last.each
        end # end of YAML.load(....).each
      end # end of ActiveRecord::Base.transaction
    end # end of task :load_from_yaml
  end # end of namespace :demo_project
end # end of namespace :redmine
