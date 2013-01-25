class PartyFoul::ExceptionHandler
  attr_accessor :exception, :env

  def self.handle(exception, env)
    PartyFoul.adapter.handle(exception, env)
  end

  def initialize(exception, env)
    self.exception = exception
    self.env       = env
  end

  def run
    if issue = find_issue
      update_issue(issue)
    else
      create_issue
    end
  end

  def find_issue
    unless issue = PartyFoul.github.search.issues(owner: PartyFoul.owner, repo: PartyFoul.repo, state: 'open', keyword: fingerprint).issues.first
      issue = PartyFoul.github.search.issues(owner: PartyFoul.owner, repo: PartyFoul.repo, state: 'closed', keyword: fingerprint).issues.first
    end

    issue
  end

  def stack_trace
    exception.backtrace.map do |line|
      if matches = extract_file_name_and_line_number(line)
        "<a href='../tree/master/#{matches[2]}#L#{matches[3]}'>#{line}</a>"
      else
        line
      end
    end.join("\n")
  end

  def create_issue
    issue = PartyFoul.github.issues.create(PartyFoul.owner, PartyFoul.repo, title: issue_title, body: issue_body, labels: ['bug'])
    PartyFoul.github.issues.comments.create(PartyFoul.owner, PartyFoul.repo, issue['number'], body: comment_body)
  end

  def update_issue(issue)
    unless issue.key?('labels') && issue['labels'].include?('wontfix')
      params = {body: update_body(issue['body']), state: 'open'}

      if issue['state'] == 'closed'
        params[:labels] = ['bug', 'regression']
      end

      PartyFoul.github.issues.edit(PartyFoul.owner, PartyFoul.repo, issue['number'], params)
      PartyFoul.github.issues.comments.create(PartyFoul.owner, PartyFoul.repo, issue['number'], body: comment_body)
    end
  end

  def issue_title
    line = exception.backtrace.select {|p| p =~ /#{app_root}/ }.first
    name_and_number = extract_file_name_and_line_number(line)[1]
    "#{exception} - #{name_and_number}"
  end

  def fingerprint
    Digest::SHA1.hexdigest(issue_title)
  end

  def update_body(body)
    begin
      current_count = body.match(/<th>Count<\/th><td>(\d+)<\/td>/)[1].to_i
      body.sub!("<th>Count</th><td>#{current_count}</td>", "<th>Count</th><td>#{current_count + 1}</td>")
      body.sub!(/<th>Last Occurance<\/th><td>.+<\/td>/, "<th>Last Occurance</th><td>#{occurred_at}</td>")
      body
    rescue
      issue_body
    end
  end

  def params
    if env["action_dispatch.parameter_filter"]
      parameter_filter = ActionDispatch::Http::ParameterFilter.new(env["action_dispatch.parameter_filter"])
      parameter_filter.filter(env['action_dispatch.request.path_parameters'])
    else
      env['QUERY_STRING']
    end
  end

  def issue_body
    compile_template(PartyFoul.issue_template)
  end

  def comment_body
    compile_template(PartyFoul.comment_template)
  end

  def compile_template(template)
    template.gsub(/:\w+/) do |method|
      self.send(method.split(':').last)
    end
  end

  def occurred_at
    Time.now.strftime('%B %d, %Y %H:%M:%S %z')
  end

  def ip_address
    env['REMOTE_ADDR']
  end

  def http_headers
    "<table>#{http_header_hash.map { |key, value| "<tr><th>#{key}</th><td>#{value}</td></tr>" }.join}</table>"
  end

  private

  def http_header_hash
    env.keys.select { |key| key =~ /^HTTP_(\w+)/ && !(PartyFoul.filtered_http_headers || []).include?($1.split('_').map(&:capitalize).join('-')) }.sort.inject({}) do |hash, key|
      hash[key.split('HTTP_').last.split('_').map(&:capitalize).join('-')] = env[key]
      hash
    end
  end

  def app_root
    if defined?(Rails)
      Rails.root
    else
      Dir.pwd
    end
  end

  def file_and_line_regex
    /#{app_root}\/((.+?):(\d+))/
  end

  def extract_file_name_and_line_number(backtrace_line)
    backtrace_line.match(file_and_line_regex)
  end
end
