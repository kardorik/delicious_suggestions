require 'rubygems'
require 'net/https'
require 'httpclient'
require 'rexml/document'
require 'json'
require 'mysql'
require 'ruby-debug'

def avoid_throttling
    puts "waiting to avoid being throttled"
    sleep(2)
end

def get_bookmark_content(url)
  url_escaped = URI.escape(url)
  url_parsed = URI.parse(url_escaped)
  puts "url parsed:"
  puts url_parsed

  client = HTTPClient.new
  resp = client.get(url_parsed)
  return resp
end

def get_your_bookmarks(username, password)
  conn = Mysql.new('localhost', 'root', mysql_password, 'delicious_suggestions')

  # cleanup tables
  conn.query("DELETE FROM users")
  conn.query("DELETE FROM bookmarks")
  conn.query("DELETE FROM bookmarks_users")
  # cleanup content directory


  # insert your name in the users table
  conn.query("INSERT INTO users (name) VALUES ('#{username}')")
  your_user_id = conn.insert_id

  # get your bookmarks
  resp = "";
  begin
    http = Net::HTTP.new("api.del.icio.us", 443)
    http.use_ssl = true
    http.start { |http|
      #req = Net::HTTP::Get.new("/v1/tags/get", {"User-Agent" => "riccardot.com delicious suggestions"})
      req = Net::HTTP::Get.new("/v1/posts/all", {"User-Agent" => "riccardot.com delicious suggestions"})
      req.basic_auth(username, password)
      response = http.request(req)
      resp = response.body
    }
    avoid_throttling
  rescue SocketError
    raise "Host #{host} not reachable"
  end

  begin
    #  XML Document
    doc = REXML::Document.new(resp)    
    # iterate over each element <tag count="200" tag="Rails"/>
    # build the list of all url you posted
    your_urls = Hash.new
    doc.root.elements.each { |elem|
      #print elem.attributes['tag']  + " -> " + elem.attributes['count'] + "\n"
      url = elem.attributes['href']
      url_signature = elem.attributes['hash']
      # insert url in bookmarks
      conn.query("INSERT INTO bookmarks (url, signature) VALUES ('#{url}', '#{url_signature}')")
      your_bookmark_id = conn.insert_id
      # add relation users-bookmarks
      conn.query("INSERT INTO bookmarks_users (user_id, bookmark_id) VALUES ('#{your_user_id}', '#{your_bookmark_id}')")

      # download content of bookmark
      bookmark_content = get_bookmark_content(url).content
      fp = File.new("./content/bookmark_id_#{your_bookmark_id}.html", "w")
      fp << bookmark_content
      fp.close

      puts "#{url} -> #{url_signature}"
    }
  rescue REXML::ParseException => e
    puts "error parsing XML #{e.to_s}"
  end
end

def get_other_bookmarks(username)
  # for each url find users that also posted that url
  count = 0
  maxed_out_urls = Array.new

  conn_other = Mysql.new('localhost', 'root', mysql_password, 'delicious_suggestions')
  your_user_id = conn_other.query("SELECT id FROM users WHERE name='#{username}'").fetch_row[0]
  your_url_ids = conn_other.query("SELECT bookmark_id FROM bookmarks_users WHERE user_id='#{your_user_id}'")
  your_url_ids.each { |your_url_id|
    url_signature = conn_other.query("SELECT signature FROM bookmarks WHERE id='#{your_url_id}'").fetch_row[0]
    begin      
      http_feed = HTTPClient.new
      feed_path = "http://feeds.delicious.com/v2/json/url/#{url_signature}?count=100"
      #puts "using feed path:#{feed_path}"
      response = http_feed.get(feed_path, {"User-Agent" => "riccardot.com delicious suggestions"})
      content = response.body.content
      content_parsed = JSON.parse(content)
      puts "[#{count}] extracting other users for your url id: #{your_url_id}"
      user_count = 0
      content_parsed.each { |other_user_data|
        other_user = other_user_data["a"]
        your_urls[url].other_users << other_user
        if other_users_weights.has_key? other_user
          other_users_weights[other_user] = other_users_weights[other_user] + 1
        else
          other_users_weights[other_user] = 1
        end
        user_count = user_count + 1
        puts "-- was recently posted also by #{other_user}"
      }
      puts "   * posted by #{user_count} users *"
      if user_count >= 99
        maxed_out_urls << url
      end
      count = count + 1
      #if count > 5
      #    break
      #end
      avoid_throttling
    rescue SocketError
      raise "Host " + host + " nicht erreichbar"
    end
  }
end

debugger

username = "" # your del.icio.us username
password = "" # your del.icio.us password
mysql_password = "" # your local database password

#get_your_bookmarks(username, password)
get_other_bookmarks(username)

puts "done"
