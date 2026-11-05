# Tests the groupmate API against a real store.
#
#   GROUPMATE_API_KEY=gm_… GROUPMATE_PRODUCT_IDS=111,222 ruby test.rb
#
# The lifecycle test leaves one group behind (no deletes). Delete it yourself before running again.
# Without GROUPMATE_PRODUCT_IDS the lifecycle test is skipped; the rest still runs.
require "minitest/autorun"
require_relative "client"

class GroupmateApiTest < Minitest::Test
  API = Groupmate.new
  MISSING_ID = 999_999_999
  UNKNOWN_PRODUCT = "1" # valid product ID that doesn't exist in any store

  def assert_error(res, status, code)
    assert_equal [status, code], [res.status, res.error_code], res.body.inspect
  end

  def member_ids(group) = group["members"].map { _1["product_id"] }
  def group_ids(res) = res.body["groups"].map { _1["id"] }

  # --- read-only -----------------------------------------------------------

  def test_invalid_key
    assert_error Groupmate.new(api_key: "gm_invalid").list, 401, "invalid_api_key"
  end

  def test_list
    res = API.list(per_page: 1)
    assert_equal 200, res.status
    assert_kind_of Array, res.body["groups"]
    assert_operator res.body["groups"].size, :<=, 1
    assert_equal %w[next_page page per_page total total_pages], res.body["pagination"].keys.sort
    assert_equal 1, res.body.dig("pagination", "per_page")
  end

  def test_per_page_is_capped_at_100
    assert_equal 100, API.list(per_page: 500).body.dig("pagination", "per_page")
  end

  def test_invalid_pagination
    assert_error API.list(page: 0), 400, "invalid_pagination"
    assert_error API.list(per_page: 0), 400, "invalid_pagination"
  end

  def test_invalid_product_id_filter
    assert_error API.list(product_id: "abc"), 400, "invalid_product_id"
  end

  def test_get_missing
    assert_error API.get(MISSING_ID), 404, "not_found"
  end

  # --- failing writes (nothing is changed) ----------------------------------

  def test_delete_missing
    assert_error API.delete(MISSING_ID), 404, "not_found"
  end

  def test_parameter_missing
    assert_error API.request(:post, "/groups", body: {}), 400, "parameter_missing"
  end

  def test_no_product_ids
    assert_error API.create(title: "x"), 422, "no_product_ids"
    assert_error API.create(title: "x", products: []), 422, "no_product_ids"
  end

  def test_invalid_product_ids
    res = API.create(products: [{ id: "abc" }])
    assert_error res, 422, "invalid_product_ids"
    assert_equal ["abc"], res.body.dig("error", "details", "invalid_product_ids")
  end

  def test_no_products_found
    assert_error API.create(products: [{ id: UNKNOWN_PRODUCT }]), 422, "no_products_found"
  end

  # --- lifecycle (creates one group, never deletes) -------------------------

  def test_group_lifecycle
    a, b = Groupmate.product_ids
    skip "Set GROUPMATE_PRODUCT_IDS to 2 product IDs to run the lifecycle test" unless a && b
    taken = API.grouped([a, b])
    flunk taken.map { |pid, g| "Product #{pid} is already in group ##{g['id']}. Delete it first." }.join("\n") if taken.any?

    # Create a draft: GID is normalized, order kept, unknown product skipped
    title = "groupmate api test #{Time.now.to_i}"
    res = API.create(
      title:, option_title: "Color", display_style: "color_swatch", publish: false,
      products: [{ id: "gid://shopify/Product/#{a}", swatch_title: "A" },
                 { id: b, swatch_color: "#0000ff" },
                 { id: UNKNOWN_PRODUCT }]
    )
    assert_equal 201, res.status, res.body.inspect
    id = res.body["id"]
    puts "\n  created group ##{id}, left in place (delete it yourself)"
    assert_equal false, res.body["published"]
    assert_equal [a, b], member_ids(res.body)
    assert_equal "A", res.body["members"][0]["swatch_title"]
    assert_equal [UNKNOWN_PRODUCT], res.body["skipped_product_ids"]
    assert_empty Array(res.body["warnings"])

    # Get + filters
    got = API.get(id)
    assert_equal 200, got.status
    assert_equal [title, [a, b]], [got.body["title"], member_ids(got.body)]
    assert_includes group_ids(API.list(product_id: a)), id
    assert_includes group_ids(API.list(product_id: "gid://shopify/Product/#{b}")), id
    assert_includes group_ids(API.list(search: title, published: false)), id
    refute_includes group_ids(API.list(search: title, published: true)), id

    # A product can only be in one group
    res = API.create(products: [{ id: a }])
    assert_error res, 422, "already_grouped"
    assert_equal [a], res.body.dig("error", "details", "already_grouped_product_ids")

    # Partial update: only the title changes, members and swatches stay
    res = API.update(id, title: "#{title} (renamed)", publish: false)
    assert_equal 200, res.status, res.body.inspect
    assert_equal ["#{title} (renamed)", false, [a, b]], [res.body["title"], res.body["published"], member_ids(res.body)]
    assert_equal "A", res.body["members"][0]["swatch_title"]

    # Reorder, clear a swatch with null, keep unsent swatch fields
    res = API.update(id, publish: false, products: [{ id: b }, { id: a, swatch_title: nil }])
    assert_equal 200, res.status, res.body.inspect
    assert_equal [b, a], member_ids(res.body)
    assert_equal "#0000ff", res.body["members"][0]["swatch_color"]
    assert_nil res.body["members"][1]["swatch_title"]
    assert_equal [0, 1], res.body["members"].map { _1["position"] }

    # Publish and remove a product
    res = API.update(id, publish: true, products: [{ id: b }])
    assert_equal 200, res.status, res.body.inspect
    assert_equal [true, [b]], [res.body["published"], member_ids(res.body)]
    assert_empty group_ids(API.list(product_id: a))

    # Published groups can't go back to draft
    assert_error API.update(id, publish: false), 422, "cannot_unpublish"
  end
end
