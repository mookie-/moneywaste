#!/usr/bin/env ruby
# encoding: iso-8859-1
require "rubygems"
require "nokogiri"
require "mechanize"
require "time"
require "sqlite3"
require "gruff"

def getfromamazon(year_start, year_end)

  xpath_products  = "div/div/div/ul/li/a/span[2]"
  xpath_prices    = "div/ul/li[4]/span[2]"
  xpath_pages     = "/html/body/div/div/div/div/div/div[6]/div[2]/strong"
  xpath_dates     = "div/h2"
  xpath_orderid  = "div/ul/li/span[2]/a"

  translate = { "Januar" => "January",
                "Februar" => "February",
                "März" => "March",
                "April" => "April",
                "Mai" => "May",
                "Juni" => "June",
                "Juli" => "July",
                "August" => "August",
                "September" => "September",
                "Oktober" => "October",
                "November" => "November",
                "Dezember" => "December"
              }

  login_url = "https://www.amazon.de/ap/signin?_encoding=UTF8&openid.assoc_handle=deflex&openid.claimed_id=http%3A%2F%2Fspecs.openid.net%2Fauth%2F2.0%2Fidentifier_select&openid.identity=http%3A%2F%2Fspecs.openid.net%2Fauth%2F2.0%2Fidentifier_select&openid.mode=checkid_setup&openid.ns=http%3A%2F%2Fspecs.openid.net%2Fauth%2F2.0&openid.ns.pape=http%3A%2F%2Fspecs.openid.net%2Fextensions%2Fpape%2F1.0&openid.pape.max_auth_age=0&openid.return_to=https%3A%2F%2Fwww.amazon.de%2Fgp%2Fyourstore%2Fhome%3Fie%3DUTF8%26ref_%3Dgno_signin"

  config_file = "#{ENV['HOME']}/.moneywaste"

  if File.exists?(config_file)

    config = {}

    File.foreach(config_file) do |line|
      line.strip!
      if (line[0] != ?# and line =~ /\S/ )
        i = line.index('=')
        if (i)
          config[line[0..i - 1].strip] = line[i + 1..-1].strip
        else
          config[line] = ''
        end
      end
    end

  end

  orderslist = Array.new

  @agent = Mechanize.new do |agent|
    agent.user_agent_alias = 'Linux Firefox'
    agent.follow_meta_refresh = true
    agent.redirect_ok = true
  end

  @agent.get(login_url)
  form = @agent.page.forms[1]
  form.email = config["email"]
  form['ap_signin_existing_radio'] = "1"
  form.password = config["password"]
  @agent.submit(form)

  for i in year_start..year_end

  orders_url = "https://www.amazon.de/gp/css/order-history/ref=oss_pagination?ie=UTF8&orderFilter=year-#{i}&search=&startIndex="

    index = 0

    while true

      file = @agent.get_file("#{orders_url}#{index}")
      no = Nokogiri::HTML(file)

      pages = no.xpath('/html/body/div/div/div/div/div/div[6]/div[2]/strong').first.content

      puts "Getting Orders... Year: #{i}, site #{pages.split[1]} from #{pages.split[3]}"

      no.css('div.action-box.rounded').each do |order|

        complete_name = ''
        order.xpath(xpath_products).each do |name|
          complete_name = "#{complete_name} || #{name.content.force_encoding("iso-8859-1").strip!}"
        end
        datum = order.xpath(xpath_dates).first.content.force_encoding("iso-8859-1").gsub(/[[:alpha:]]+/, translate)
        orderslist.push({ "name"  => complete_name[4..-1],
                          "price" => order.xpath(xpath_prices).first.content[4..-1],
                          "order_id" => order.xpath(xpath_orderid).first.content,
                          "date"  => Time.parse(datum)
                        })

      end

      if(pages.split[1] == pages.split[3])
        break
      end

      index = index + 7

    end

    puts "Check database and save orders"

    db = SQLite3::Database.new( "moneywaste.sqlite" )

    orderslist.each do |order|

      order_exist = db.get_first_value( "select count(id) from moneywaste where name = '#{order['name']}' and price = '#{order['price']}' and order_id = '#{order['order_id']}' and date = '#{order['date']}'" )

      unless order_exist > 0
        db.execute( "insert into moneywaste ('name','price','order_id','date') values ('#{order['name']}','#{order['price']}','#{order['order_id']}','#{order['date']}')" )
      end

      if order_exist > 1
        puts "ERROR: order with name #{order['name']} is #{order_exist} times in the database"
      end

    end

  end

end

def draw(year_start, year_end)

  db = SQLite3::Database.new( "moneywaste.sqlite" )

  graph = Gruff::Line.new(1000)
  graph.title = "Amazon"
  graph.theme = {
    :colors => ['#3B5998'],
    :marker_color => 'silver',
    :font_color => '#333333',
    :background_colors => ['white', 'silver']
  }
  graph.theme_keynote

  data = Array.new

  puts "Get data from database"

  labels = Hash.new
  labels_index = 0

  for year in year_start..year_end

    for i in 1..12

      if labels_index.modulo(3) == 0
        labels[labels_index] = "#{i}/#{year}"
      end
      labels_index += 1

      month = "%02d" % i
      sum = db.get_first_value( "select sum(price) from moneywaste where date like '#{year}-#{month}%'" )
      if sum == nil
        sum = 0
      end
      data.push(sum)

    end
  
  end

  graph.data("Summe", data)
  graph.marker_count = 4
  graph.labels = labels

  puts "Draw graph"

  graph.write('foo.png')
end

year_start = ARGV[0]
year_end = ARGV[1]

if ARGV.size < 2
  p "Usage: moneywaste.rb startyear endyear"
else
  case ARGV[2]
  when "data"
    getfromamazon(year_start, year_end)
  when "draw"
    draw(year_start, year_end)
  else
    getfromamazon(year_start, year_end)
    draw(year_start, year_end)
  end
end
