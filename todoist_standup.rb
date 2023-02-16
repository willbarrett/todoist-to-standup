require 'bundler/setup'
require 'dotenv/load'
require 'business_time'
require 'httparty'
require 'slack-ruby-client'

TODOIST_REST_API_BASE = "https://api.todoist.com/rest/v2"
TODOIST_SYNC_API_BASE = "https://api.todoist.com/sync/v9"

Slack.configure do |config|
  config.token = ENV['SLACK_API_TOKEN']
end

slack_client = Slack::Web::Client.new

#slack_client.auth_test

token = ENV['TODOIST_API_KEY']
auth_header = {
  'Authorization' => "Bearer #{token}"
}

# Use the business_time gem to find the last business day
#last_business_day = 1.business_day.ago.beginning_of_day
last_business_day = 1.day.ago


standup_update = ""

projects_response = HTTParty.get("#{TODOIST_REST_API_BASE}/projects", {
  headers: auth_header
})

projects = JSON.parse(projects_response.body).collect {|p| p['id'] if p['parent_id'] == "2307653303" }.compact

yesterday = "What did you do since yesterday?\n"

completed_activities = []
projects.each do |project|
  activity_response = HTTParty.get("#{TODOIST_SYNC_API_BASE}/activity/get", {
    headers: auth_header,
    query: {
      object_type: "item",
      parent_project_id: project,
      event_type: "completed"
    }
  })
  activities = JSON.parse(activity_response.body)["events"].each do |activity|
    if Time.parse(activity["event_date"]) > last_business_day.to_time
      completed_activities << " - Completed: #{activity['extra_data']['content']}\n"
    end
  end
end

completed_activities.uniq.each do |activity|
  yesterday << activity
end
puts yesterday
puts "Did you do anything else? (comma separated)"
more_yesterday = gets.chomp.split(',').map(&:strip)

if more_yesterday.any?
  more_yesterday.each do |itm|
    yesterday << " - Completed: #{itm}\n"
  end
end
standup_update << yesterday

today = ""
today << "What will you do today?\n"

todo_response = HTTParty.get("#{TODOIST_REST_API_BASE}/tasks", {
  headers: auth_header,
  query: {
    'filter' => '(today | overdue) & ##Work'
  }
})

JSON.parse(todo_response.body).each do |t|
  today << " - #{t['content']}\n"
end

puts today
puts "Will you do anything else? (comma separated)"
more_today = gets.chomp.split(',').map(&:strip)
if more_today.any?
  more_today.each do |itm|
    today << " - #{itm}\n"
  end
end
standup_update << today

puts "Anything blocking your progress? (separated by commas):"
blockers = gets.chomp.split(',').map(&:strip)

if blockers.any?
  standup_update << "Anything blocking your progress?\n"
  blockers.each do |blocker|
    standup_update << " - #{blocker}\n"
  end
end

puts standup_update

IO.popen('pbcopy', 'w') { |f| f << standup_update }

puts "\n\nStandup update has been copied to clipboard"
