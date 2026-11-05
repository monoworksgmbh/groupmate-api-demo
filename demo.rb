# Walkthrough of the groupmate API: list → create (draft) → get → update (publish) → filter.
#
#   GROUPMATE_API_KEY=gm_… GROUPMATE_PRODUCT_IDS=111,222 ruby demo.rb
#
# The created group is NOT deleted. Delete it yourself before running again.
require_relative "client"

def step(title, res)
  puts "\n== #{title} → #{res.status}"
  puts JSON.pretty_generate(res.body) if res.body
  abort "\n!! #{res.error_code || 'unexpected error'}" unless res.ok?
  res.body
end

api = Groupmate.new
a, b = Groupmate.product_ids
abort "Set GROUPMATE_PRODUCT_IDS to 2 product IDs from your store" unless a && b

taken = api.grouped([a, b])
abort taken.map { |pid, g| "Product #{pid} is already in group ##{g['id']} (#{g['title']}). Delete it first." }.join("\n") if taken.any?

step "List groups (first 3)", api.list(per_page: 3)

group = step "Create a draft with magicfill", api.create(
  title: "groupmate demo",
  option_title: "Color",
  display_style: "color_swatch",
  publish: false,
  magicfill: true,
  products: [{ id: a }, { id: "gid://shopify/Product/#{b}" }]
)
id = group["id"]

step "Get group ##{id}", api.get(id)
step "Publish and reverse the order", api.update(id, publish: true, products: [{ id: b }, { id: a }])
step "Find the group by product #{a}", api.list(product_id: a)

puts <<~TXT

  Done. Group ##{id} was left in place. Delete it in the app or with:
    curl -X DELETE #{ENV.fetch("GROUPMATE_BASE_URL", "https://groupmate.fly.dev/api/v1")}/groups/#{id} -H "Authorization: Bearer $GROUPMATE_API_KEY"
TXT
