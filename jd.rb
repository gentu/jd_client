#!/usr/bin/ruby

require 'rubygems'
require 'mechanize'
require 'json'
require 'yaml'
require 'optparse'
require 'find'

class Site_JD
  def initialize
    @settings_file = ENV['HOME'] + '/.jd_config.yml'

    @agent = Mechanize.new
    @agent.cookie_jar.load ENV['HOME'] + '/.jd_cookies.yml' rescue puts 'No cookies.yml'
    @agent.user_agent = 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/46.0.2490.80 Safari/537.36'
    @agent.follow_meta_refresh = true

    @bot = false
  end

  def set_user username, password
    @settings['username'] = username
    @settings['password'] = password
    save_settings
  end

  def load_settings
    begin
      @settings = YAML.load_file(@settings_file)
    rescue Errno::ENOENT
      @settings = Hash.new
      save_settings
    end
  end

  def save_settings
    File.open(@settings_file, "w") do |file|
      file.write @settings.to_yaml
    end
  end

  def save_cookies
    @agent.cookie_jar.save_as ENV['HOME'] + '/.jd_cookies.yml', session: true
  end

  def login
#    url = 'http://signin.jd.com/new/logoutService.html'
 #   url = 'http://csc.jd.com/log.ashx?type1=J&type2=A&pin=-&uuid=621972987&sid=621972987|8&referrer=http%253A%252F%252Fsignin.jd.com%252F&jinfo=UA-J2011-1||1||24-bit||1920x1080||ja||UTF-8||Sign%20In%20JD||signin.jd.com||-||linux||firefox||41.0||1446718375||1446801960||1446810525||8||1||www.jd.ru||-||referral||-||0||-||-&data=1446810524507&callback=jQuery1720044723044518862665_1446810524429'
  #  p @agent.post(url)
  #  return
 #   p @agent.cookie_jar.jar
#    return
    url = 'http://signin.joybuy.com/new/loginService.html'
    params = { 'email' => @settings['username'], 'password' => @settings['password'] }
    page = @agent.post(url, params).body
    json = JSON.parse(page)['map']
    set_userpin json['userPin']
    @agent.post( json['returnUrl'] )
    p @agent.post('http://joybuy.com/sync/tkur.html?callback=null')
    p @agent.post('http://jd.ru/sync/sp.html', 'koki' => { 'TrackID' => @agent.cookie_jar.jar['joybuy.com']['/']['TrackID'].value } )
    hello
    save_cookies
    #p @agent.cookie_jar.jar['jd.com']['/']['ept.ceshi5.com'].value
  end

  def hello
    url = 'http://signin.jd.com/new/helloService.html'
    page = @agent.post(url)
    puts page.body.include?('sign-out') ? 'Login sucessful' : 'Login failed'
  end

  def set_userpin pin
    if @settings['userPin'] != pin
      @settings['userPin'] = pin
      save_settings
      puts 'Set new userPin: ' + @settings['userPin']
    end
  end

  def load_cart
    url = 'http://c.joybuy.com/cart/sync_cart.html'
    page = @agent.post(url).body.sub('null(','').chop!
    json = JSON.parse(page)['cart']
    begin
      puts json['ga']['pnames'].sub('null,','').sub(',',"\n")
    rescue Exception=>e
      puts 'Cart is null'
      return nil
    end
    puts json['countryName']
    puts json['currency']
    puts json['cartTotal']
    puts json['cartSkusCount']
    puts json['cartToBuySkusCount']
    set_userpin json['userPin']
  end

  def my_coupons
    url = 'http://c.joybuy.com/order/sync_user_coupon.html'
    page = @agent.post(url).body.sub('null(','').chop!
    json = JSON.parse(page)['coupons']
    #p json
    return nil if json.nil?
    json.each do |coupon|
      puts coupon['rightItemSlogan'].sub(',',"\n") + coupon['availableTimesSlogan']
    end
  end

  def my_orders
    url = 'http://o.joybuy.com/order/orderList.html'
    page = @agent.post(url).parser
    page.css('div.p-name/a').each do |item|
      puts item.text
    end
  end

  def add_to_cart sku
#https://c.jd.ru/cart/add_to_cart_ajax.html?t=1498135090917&sid=196333&venderid=44&vendername=Huayang%20Trading%20LLC&scount=1&sCountryId=2468&dcId=-1&storeId=-1&carrierId=13801114&countryId=2285&callback=addcartCallback&_=1498135090924
    url = 'http://c.joybuy.com/cart/add_to_cart_ajax.html'
    params = { 'scount' => 1, 'sid' => sku, 'carrierId' => 13301109, 'countryId' => 2285 }
    page = @agent.post(url, params).body.sub('null(','').chop!
    item = JSON.parse(page)['hasAdded']
    puts item ? 'Item has added' : 'Item NOT added'
  end

  def order sku,coupon
    url = 'http://c.joybuy.com/order/sync_order_cart.html?reqCode=003'
    params = { 'countryId' => 2285, 'coupon' => coupon, 'userName' => @settings['userPin'], 'skus' => sku + ',1,0,' }
    page = @agent.post(url, params).body.sub('null(','').chop!
    json = JSON.parse(page)['cart']
    begin
      carrier = json['sellerCartList'][0]['cartItemDetailList'][0]['carrierId'].to_s
      puts json['ga']['pnames'].sub('null,','').sub(',',"\n")
      puts 'Coupon: ' + json['usedCoupon'].to_s
      puts json['cartSubTotal'] + ' - ' + json['coupon']['couponAmount'].to_s + ' = ' + json['cartTotal']
      puts 'Can buy pcs: ' + json['cartToBuySkusCount'].to_s
    rescue
      p json
      puts 'Error order'
    end
    puts "Submit order is: " + submit_order(sku,coupon,carrier).to_s
  end

  def submit_order sku,coupon,carrier
    url = 'http://c.joybuy.com/order/submit_order.html?reqCode=008'
    params = { 'address' => @settings['AddressID'], 'coupon' => coupon, 'payType' => 1, 'userName' => @settings['userPin'], 'skus' => sku + ',1,0,' }
    page = @agent.post(url, params).body
    begin
      json = JSON.parse(page.sub('null(','').chop!)
      return json['submitSuccess']
    rescue
      p json
      puts 'Error submit_order'
      return false
    end
  end

  def loop_order sku,coupon,carrier
    puts 'loop_order sku: ' + sku + ' coupon: ' + coupon + ' carrier: ' + carrier
    600.times do |i|
      puts 'time: ' + i.to_s
      puts 'loop_order working' + ' skuID: ' + sku + ' coupon: ' + coupon
      break if submit_order(sku,coupon,carrier)
      sleep 1
    end
    puts 'loop_order is over'
  end

  def check_stock sku
    url = 'http://joybuy.com/product/skuStock.html'
    params = { 'skuId' => sku, 'callback' => 'null' }
    puts @agent.post(url, params).body.sub('null(','').chop!
  end

  def get_address_id
    url = 'http://c.joybuy.com/order/confirm_order.html'
    page_orig = @agent.post(url).parser
    page = page_orig.at('div#j-address-select').at('div.item.selected')
    page.at('div.i-detail').css('div.line').each do |line|
      puts line.text
    end
    id = page.at('input[id^=id_]')['value']
    if @settings['AddressID'] != id
      @settings['AddressID'] = id
      save_settings
      puts 'Set new AddressID: ' + @settings['AddressID']
    else
      puts 'Actual address already set'
    end
    set_userpin page_orig.at('input#userPin')['value']
  end
end

site = Site_JD.new
site.load_settings
#site.hello

OptionParser.new do |opts|
  opts.banner = "Usage: jd [options]"
  opts.separator ""
  opts.separator "Specific options:"

  opts.on( '-d', '--address', 'address id to JD.ru' ) do
    site.get_address_id
  end
  opts.on( '-l', '--login', 'login to JD.ru' ) do
    site.login
  end
  opts.on( '-h', '--hello', 'hello to JD.ru' ) do
    site.hello
  end
  opts.on( '-c', '--cart', 'cart to JD.ru' ) do
    site.load_cart
  end
  opts.on( '-m', '--coupons', 'my coupons to JD.ru' ) do
    site.my_coupons
  end
  opts.on( '-r', '--myorders', 'my orders to JD.ru' ) do
    site.my_orders
  end
  opts.on( '-t', '--stock [SKU]', 'check stock to JD.ru' ) do |sku|
    site.check_stock sku
  end
  opts.on( '-a', '--add [SKU]', 'add to cart to JD.ru' ) do |sku|
    site.add_to_cart sku
  end
  opts.on( '-o', '--order [SKU],[COUPON]', Array, 'order to JD.ru' ) do |order|
    sku = order[0]
    coupon = order[1]
    site.order sku,coupon
  end
  opts.on( '-p', '--loop [SKU],[COUPON]', Array, 'loop order to JD.ru' ) do |order|
    sku = order[0]
    coupon = order[1]
    site.loop_order sku,coupon,carrier
  end
  opts.on( '-s', '--setuser username,password', Array, 'Set username and password' ) do |user|
    username = user[0]
    password = user[1]
    site.set_user username, password
  end
end.parse!

#site.login
#site.get_token
#site.create_folder 123
#remove_file
#site.save_cookies
