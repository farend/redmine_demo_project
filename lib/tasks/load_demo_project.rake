desc 'Load Redmine Demo-data using yaml file'
namespace :redmine do
  task :load_demo_project => :environment do
    begin
      demo_data_yaml_path = Dir[File.join(Rails.root, 'plugins', 'redmine_demo_project', 'db', 'demo_data.yml')][0]
      Redmine::DemoData::Loader.load(demo_data_yaml_path)
      puts "Demo data loaded."
    rescue Redmine::DemoData::InvalidDemoData => error
      puts error.message
    rescue => error
      puts "Error: " + error.message
      puts "Demo data was not loaded."
    end
  end
end
