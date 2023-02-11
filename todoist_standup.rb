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
last_business_day = 1.business_day.ago.beginning_of_day


standup_update = "What did you do since yesterday?\n"

projects_response = HTTParty.get("#{TODOIST_REST_API_BASE}/projects", {
  headers: auth_header
})

projects = JSON.parse(projects_response.body).collect {|p| p['id'] if p['parent_id'] == "2307653303" }.compact

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
  standup_update << activity
end

standup_update << "What will you do today?\n"

todo_response = HTTParty.get("#{TODOIST_REST_API_BASE}/tasks", {
  headers: auth_header,
  query: {
    'filter' => '(today | overdue) & ##Work'
  }
})

JSON.parse(todo_response.body).each do |t|
  standup_update << " - #{t['content']}\n"
end


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

# puts "\n"
# puts "OK to post? (y/n)"
# send_approval = gets.chomp.strip == "y"

# if send_approval
#   slack_client.chat_postMessage(
#     channel: "#test-bot-channel",
#     text: "Hello from Ruby!",
#     as_user: true
#   )
# end

