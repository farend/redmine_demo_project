module Redmine
  module DemoData
    class InvalidDemoData < Exception; end

    module Loader
      class << self
        def load(demo_data_yaml_path)
          ActiveRecord::Base.transaction do
            YAML::load(ERB.new(File.read(demo_data_yaml_path)).result).each do |yaml|
              yaml.last.each do |table_name, records|
                records.each do |record|
                  # recordは配列となっており、record[0]=yamlデータ上の識別子、record[1]=yaml化されたattributesで構成されている
                  # そのため、実際に登録したいデータのattributesを、record.lastとして参照している
                  # (ex)
                  # testuser1:                  -- record[0]
                  #   login: 'testuser1'        -- record[1] ==> yaml_attributes
                  #   password: 'testpassword1' -- record[1]
                  yaml_attributes = record.last
  
                  # テーブル毎にデモデータを登録する
                  # テーブル名に応じて、`entry_テーブル名の単数形` メソッドを呼び出してデータを登録する
                  # (ex)
                  # table_name が `users` であれば、 `entry_user(yaml_attributes)` を呼び出し
                  table_names = %w(users trackers projects members versions files issues wikis wiki_pages)
                  self.send("entry_#{table_name.singularize}", yaml_attributes) if table_names.include?(table_name)
                end
              end
            end
          end
        end

        # ユーザーを登録する
        def entry_user(yaml_attributes)
          entry_demo_data('User', yaml_attributes, 'login') do |user|
            user.login = yaml_attributes['login']
            user.password = yaml_attributes['password']
            user.password_confirmation = yaml_attributes['password_confirmation']
            user.admin = false
            user.generate_password = 0
            user.must_change_passwd = 0
            user.register
            user.activate
          end
        end

        # トラッカーを登録する
        def entry_tracker(yaml_attributes)
          Tracker.skip_callback(:destroy, :before, :check_integrity)
          tracker = entry_demo_data('Tracker', yaml_attributes, 'name') do |tracker|
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
        end

        # プロジェクトを登録する
        def entry_project(yaml_attributes)
          tracker_names = yaml_attributes.delete('tracker_names')
          entry_demo_data('Project', yaml_attributes, 'identifier') do |project|
            trackers = Tracker.where('name IN (?)', tracker_names)
            project.trackers = trackers
          end
        end

        # メンバーを登録する
        def entry_member(yaml_attributes)
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
        end

        # バージョンを登録する
        def entry_version(yaml_attributes)
          project_identifier = yaml_attributes.delete('project_identifier')
          project = Project.find_by identifier: project_identifier
          yaml_attributes['project_id'] = project.id
          entry_demo_data('Version', yaml_attributes, ['name', 'project_id']) do |version|
            project = Project.find_by identifier: project_identifier
            version.project = project
          end
        end
  
        # ファイルを登録する
        def entry_file(yaml_attributes)
          project_identifier = yaml_attributes.delete('project_identifier')
          project = Project.find_by identifier: project_identifier
          version_name = yaml_attributes.delete('version_name')
          attachment_filename = yaml_attributes.delete('attachment_filename')
          attachment_description = yaml_attributes.delete('attachment_description')
          author_user_login = yaml_attributes.delete('author_user_login')
          if version = Version.find_by(project_id: project.id, name: version_name)
            # 添付ファイルのダミーデータを設定
            if attachment_filename && author_user_login
              author = User.find_by login: author_user_login
              attach_file!(version, attachment_filename, author, attachment_description)
            end
          end
        end

        # チケットを登録する
        def entry_issue(yaml_attributes)
          project_identifier = yaml_attributes.delete('project_identifier')
          assigned_user_login = yaml_attributes.delete('assigned_user_login')
          assigned_user = User.find_by login: assigned_user_login
          fixed_version_name = yaml_attributes.delete('fixed_version_name')
          issue_status_name = yaml_attributes.delete('status_name')
          tracker_name = yaml_attributes.delete('tracker_name')
          start_date = yaml_attributes.delete('start_date')
          end_date = yaml_attributes.delete('end_date')
          attachment_filename = yaml_attributes.delete('attachment_filename')
          attachment_description = yaml_attributes.delete('attachment_description')

          # チケットを新規作成する
          issue = entry_demo_data('Issue', yaml_attributes, ['subject', 'fixed_version_id'], false) do |issue|
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

          # ステータスに応じてチケットを編集-->更新する
          # (1) 進行中または終了の場合は、ステータスを「進行中」にセットする
          if issue_status_name == "進行中" || issue_status_name == "終了"
            done_ratio = rand(1..8) * 10
            update_issue_status(issue, '進行中', done_ratio, '作業に着手しました', assigned_user, start_date, start_date)
          end

          # (2)終了の場合は、ステータスを「終了」にセットする
          if issue_status_name == "終了"
            update_issue_status(issue, '終了', 100, '作業が完了しました。', assigned_user, nil, end_date) do |updated_issue|
              # 添付ファイルのダミーデータを設定
              if attachment_filename.present?
                attach_file!(updated_issue, attachment_filename, assigned_user, attachment_description)
              end
            end
          end
        end

        # チケットのステータスを更新する
        def update_issue_status(issue, status_name, done_ratio, journal_note, update_user, started_at, updated_at)
          print "Updating Issue #{issue.subject} status -> 終了..."
          # issue.reload  # MEMO: issue.reloadだと進行中で設定したjournalが上書きされるので、もう一度findする
          issue = Issue.find(issue.id)
          issue.init_journal(update_user, journal_note)
          journal = issue.current_journal
          journal.created_on = updated_at if updated_at.present?
          issue_status = IssueStatus.find_by name: status_name
          issue.status = issue_status
          issue.start_date = updated_at if started_at.present?
          # :issue.update_done_ratio_from_issue_status # MEMO: issue_statusにdone_ratioが設定されていないと有効にならない...
          issue.done_ratio =  done_ratio.to_i # 進捗率

          # ファイルの添付など付随する処理
          yield(issue) if block_given?

          begin
            issue.save!(validate: false)
            puts 'SUCCESS!'
          rescue => e
            puts "FAILD! : #{e.message}"
            raise e
          end
        end

        #
        # Wikiを登録する
        #
        def entry_wiki(yaml_attributes)
          project_identifier = yaml_attributes.delete('project_identifier')
          project = Project.find_by identifier: project_identifier
          yaml_attributes['project_id'] = project.id
          wiki = entry_demo_data('Wiki', yaml_attributes, ['project_id'], false)
        end

        #
        # WikiPage、WikiContentを登録する
        #
        def entry_wiki_page(yaml_attributes)
          # WikiPageのプロジェクト情報を取り出し＆プロジェクトをDBからロードする
          project_identifier = yaml_attributes.delete('project_identifier')
          project = Project.find_by identifier: project_identifier
          # プロジェクトのWikiデータをDBからロードする
          wiki = Wiki.find_by project_id: project.id
          return unless wiki.present?
          # WikiPageを登録するためのyaml_attributes['wiki_id']に、wikiのidをセットする
          yaml_attributes['wiki_id'] = wiki.id

          # 親ページのtitleを取り出してWikiPageを登録するためのyaml_attributes['parent_id']にセットする
          parent_title = yaml_attributes.delete('parent_title')
          parent_id = wiki.pages.find_by(title: parent_title).try(:id)
          yaml_attributes['parent_id'] = parent_id

          # WikiPageの添付ファイル情報を取り出す
          attachment_filename = yaml_attributes.delete('attachment_filename')
          attachment_description = yaml_attributes.delete('attachment_description')

          # WikiContentのattributesを取り出す
          content_attributes = yaml_attributes.delete('content')
          # WikiContentの作成者のでーたを取り出す 
          author_login = content_attributes.delete('author_login')
          author = User.find_by login: author_login
          # WikiPageをまず作成する
          wiki_page = entry_demo_data('WikiPage', yaml_attributes, ['wiki_id', 'title'], false) do |page|
            content_attributes['author_id'] = author.id
            wiki_content = page.build_content(content_attributes)
          end
          # 添付ファイルのダミーデータを設定
          if attachment_filename.present?
            attach_file!(wiki_page, attachment_filename, author, attachment_description)
          end
        end

        #
        # デモデータを登録する
        #
        def entry_demo_data(model_name, yaml_attributes, find_keys, validate = true)
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
            binding.pry
            puts "FAILD! : #{e.message}"
            raise e
          end
        end

        #
        # Attachementクラスを使ってファイルを添付するメソッド
        #
        def attach_file!(attached_obj, attachment_filename, author, attachment_description)
          begin
            print "(Saving Attachment #{attachment_filename}..."
            attachment_file_path = File.join(Rails.root, 'plugins', 'redmine_demo_project', 'files', attachment_filename)
            attachment_file = File.new(attachment_file_path)
            attachment = Attachment.new(:file => attachment_file)
            attachment.author = author
            attachment.filename = attachment_filename
            attachment.save!
            # オブジェクトにファイルを添付する
            case attached_obj.class.name
            when "Issue"
              attached_obj.save_attachments(Array.wrap({"filename" => attachment.filename,
                                                        "description" => attachment_description,
                                                        "token" => attachment.token}))
            when "Version", "WikiPage"
              Attachment.attach_files(attached_obj, Array.wrap({"filename" => attachment.filename,
                                                                "description" => attachment_description,
                                                                "token" => attachment.token}))
            end
            print 'SUCCESS!)'
          rescue => e
            print "FAILD! : #{e.message})"
            raise e
          end
        end
      end
    end
  end
end
