require 'shopify_api'
require 'discogs-wrapper'
require 'sinatra'
require 'openssl'
require 'active_support/security_utils'
require 'aws-sdk-secretsmanager'

client = Aws::SecretsManager::Client.new
get_secret_value_response = client.get_secret_value(secret_id: ENV['SECRETS_PATH'])
secrets = if get_secret_value_response.secret_string
            JSON.parse(get_secret_value_response.secret_string)
          else
            JSON.parse(Base64.decode64(get_secret_value_response.secret_binary))
          end

API_KEY = secrets['shopify-api-key']
API_SECRET = secrets['shopify-api-secret']
SHARED_SECRET = secrets['shopify-shared-secret']
SHOP_NAME = ENV['SHOP_NAME']
APP_URL = ENV['APP_URL']
DISCOGS_API_KEY = secrets['discogs-api-key']

shop_url = "https://#{API_KEY}:#{API_SECRET}@#{SHOP_NAME}.myshopify.com"
ShopifyAPI::Base.site = shop_url
ShopifyAPI::Base.api_version = '2019-04'

before do
  if !request.body.read.empty? && !request.body.empty?
    request.body.rewind
    @params = Sinatra::IndifferentHash.new
    @params.merge!(JSON.parse(request.body.read))
  end
end

get '/setup' do
  create_webhooks

  'created webhooks'
end

post '/webhook/products/update' do
  data = verify_webhook(request)
  return unauth_response if data == false

  make_sellable(data)

  return [200, 'Webhook notification received successfully. (/products/update)']
end

post '/webhook/products/create' do
  data = verify_webhook(request)
  return unauth_response if data == false

  tag_product(data)

  return [200, 'Webhook notification received successfully. (/products/create)']
end

def unauth_response
  [403, 'You are not authorized to perform this action.']
end

def verify_webhook(request)
  hmac = request.env['HTTP_X-Shopify-Hmac-Sha256']
  request.body.rewind
  data = request.body.read
  calculated_hmac = Base64.strict_encode64(OpenSSL::HMAC.digest('sha256', SHARED_SECRET, data))

  return JSON.parse(data) if ActiveSupport::SecurityUtils.secure_compare(calculated_hmac, hmac)

  false
end

def create_webhooks
  ShopifyAPI::Webhook.find(:all).each(&:destroy!)

  topics = ['products/create', 'products/update']
  topics.each do |topic|
    webhook = {
      topic: topic,
      address: "https://#{APP_URL}/webhook/#{topic}",
      format: 'json'
    }
    ShopifyAPI::Webhook.create(webhook)
  end
end

def make_sellable(product)
  product = ShopifyAPI::Product.find(product['id'])
  product.variants.first.inventory_policy = 'continue'
  product.save
end

def parse_fields(product_title)
  parts = product_title.scan(/(.*)\s+-\s+(.*)\s+?(\(.*\))/i)

  return [] if parts.empty?

  artist = parts[0][0]
  title = parts[0][1]
  { artist: artist, title: title }
end

def get_tags(artist, title)
  discogs = Discogs::Wrapper.new('bluemage.ca Shopify App 0.1', user_token: DISCOGS_API_KEY)
  search = discogs.search(title, per_page: 20, type: :release)

  tags = []

  if search.results && !search.results.empty?
    search.results.each do |result|
      next unless result.title.include? artist

      result.genre.each do |genre|
        tags.push("genre-#{genre.delete(',')}")
      end
      result.style.each do |genre|
        tags.push("genre-#{genre.delete(',')}")
      end

      break
    end
  end

  tags.push("artist-#{artist}".delete(',').downcase)
  tags
end

def tag_product(product)
  product = ShopifyAPI::Product.find(product['id'])
  product_fields = parse_fields(product.title)
  tags = get_tags(product_fields[:artist], product_fields[:title])

  tags_str = tags.join(', ')
  product.tags += ', ' unless product.tags.empty?
  product.tags += tags_str

  product.save
end
