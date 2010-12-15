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

debugger

username = "" # your del.icio.us username
password = "" # your del.icio.us password
mysql_password = "" # your local database password

# insert your name in the users table
conn = Mysql.new('localhost', 'root', mysql_password, 'delicious_suggestions')
conn.query("INSERT INTO users (name) VALUES ('#{username}')")
your_user_id = conn.insert_id

# get your bookmarks
resp = "";
begin
    http = Net::HTTP.new("api.del.icio.us", 443)
    http.use_ssl = true
    http.start { |http|
        #req = Net::HTTP::Get.new("/v1/tags/get", {"User-Agent" => "juretta.com RubyLicious 0.2"})
        req = Net::HTTP::Get.new("/v1/posts/all", {"User-Agent" => "juretta.com RubyLicious 0.2"})
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

        puts "#{url} -> #{url_signature}"
    }
rescue REXML::ParseException => e
    puts "error parsing XML #{e.to_s}"
end

puts "done"
