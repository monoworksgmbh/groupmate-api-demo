# groupmate REST API (v1)

Manage your product groups from your own tools: list, create, update and delete groups.

**Base URL:** `https://groupmate.fly.dev/api/v1`

## Authentication

1. Open groupmate in your Shopify admin and go to the **API** page.
2. Click **Create API key** and copy the key (`gm_…`). It is shown **only once**. If you lose it, revoke it and create a new one.
3. Send the key with every request:

```
Authorization: Bearer gm_your_key
```

A key has full access to your store's groups. Revoked keys stop working immediately. Keys also stop working when you uninstall groupmate.

## Quick start

```sh
curl https://groupmate.fly.dev/api/v1/groups \
  -H "Authorization: Bearer gm_your_key"
```

## Endpoints

| Method | Path | What it does |
|---|---|---|
| `GET` | `/groups` | List groups |
| `GET` | `/groups/:id` | Get one group |
| `POST` | `/groups` | Create a group |
| `PATCH` | `/groups/:id` | Update a group |
| `DELETE` | `/groups/:id` | Delete a group |

Request bodies are JSON (`Content-Type: application/json`) and wrapped in a `group` object.

### The group object

```json
{
  "id": 42,
  "title": "Summer Tee",
  "option_title": "Color",
  "display_style": "color_swatch",
  "published": true,
  "created_at": "2026-11-05T10:00:00.000Z",
  "updated_at": "2026-11-05T10:00:00.000Z",
  "members": [
    { "product_id": "7365418188877", "product_title": "Summer Tee Red", "swatch_title": "Red", "swatch_color": "#ff0000", "position": 0 },
    { "product_id": "7365418188878", "product_title": "Summer Tee Blue", "swatch_title": "Blue", "swatch_color": "#0000ff", "position": 1 }
  ]
}
```

| Field | Notes |
|---|---|
| `title` | Internal name of the group |
| `option_title` | Label shown above the swatches in your store, e.g. "Color" |
| `display_style` | `color_swatch`, `image_swatch` (product image) or `button` (text) |
| `published` | `true` if the group is shown in your store |
| `members` | The group's products, in display order |

**Product IDs** can be numeric (`7365418188877`) or GIDs (`gid://shopify/Product/7365418188877`). Responses always use the numeric form, as a string.

### List groups

```
GET /groups?page=1&per_page=20
```

| Parameter | Notes |
|---|---|
| `page` | Default `1` |
| `per_page` | Default `20`, maximum `100` |
| `product_id` | Only the group containing this product |
| `search` | Group title or product title |
| `published` | `true` or `false` |

```json
{
  "groups": [ { "id": 42, "title": "Summer Tee", "…": "…" } ],
  "pagination": { "page": 1, "per_page": 20, "total": 35, "total_pages": 2, "next_page": 2 }
}
```

`next_page` is `null` on the last page.

### Create a group

```sh
curl -X POST https://groupmate.fly.dev/api/v1/groups \
  -H "Authorization: Bearer gm_your_key" \
  -H "Content-Type: application/json" \
  -d '{
    "group": {
      "title": "Summer Tee",
      "option_title": "Color",
      "display_style": "color_swatch",
      "products": [
        { "id": "7365418188877", "swatch_title": "Red", "swatch_color": "#ff0000" },
        { "id": "7365418188878", "swatch_title": "Blue", "swatch_color": "#0000ff" }
      ]
    }
  }'
```

| Field                                    | Notes                                                                                                                                      |
| ---------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| `products`                               | **Required.** At least one product. `swatch_title` and `swatch_color` are optional.                                                        |
| `title`, `option_title`, `display_style` | Optional                                                                                                                                   |
| `publish`                                | Default `true`: the group goes live in your store right away. `false` creates a draft.                                                     |
| `magicfill`                              | Default `false`. `true` lets groupmate suggest empty titles, swatch titles and colors from the product titles. Values you send always win. |

Returns `201` with the group, plus:

- `skipped_product_ids`: products Shopify didn't find in your store. They're left out; the group is still created.
- `warnings`: e.g. `["magicfill_failed"]` if suggestions couldn't be generated. The group is still created.

### Update a group

```
PATCH /groups/:id
```

Takes the same fields as create. **Only the fields you send change.**

- **`products` is the complete new list**, in order: new products are added, missing ones are removed. Leave `products` out to keep the members as they are.
- For products already in the group, swatch fields you don't send keep their value. Send `null` to clear one.
- `publish` defaults to `true`. A published group can't be turned back into a draft (`cannot_unpublish`); delete it instead.

Returns `200` with the group, `skipped_product_ids` and `warnings`.

### Delete a group

```
DELETE /groups/:id
```

Returns `204`. The group disappears from your store right away.

## Good to know

- **Your storefront updates shortly after the response, usually within a few seconds.** The response (and any GET after it) already shows the new state; groupmate then writes it to your products in Shopify. Many changes in a row take longer, because groupmate stays within your store's Shopify API limits. You don't need to resend anything: failed Shopify updates are retried automatically.
- **A product can only be in one group.** Adding a product that's already in another group fails with `already_grouped`.
- **Large groups:** the storefront shows up to 192 products per group.

## Rate limits

Per store, across all keys:

- **120 requests per minute**
- **30 writes per minute** (create, update, delete)

Above that you get `429` with a `Retry-After` header (seconds).

## Errors

Errors always look like this:

```json
{
  "error": {
    "code": "already_grouped",
    "message": "One or more of the selected Products already belong to a group",
    "details": { "already_grouped_product_ids": ["7365418188877"] }
  }
}
```

`details` is only present for some errors. Use `code` in your code; `message` may change.

| Status | `code` | Meaning |
|---|---|---|
| 400 | `parameter_missing` | The body has no `group` object |
| 400 | `invalid_product_id` | `product_id` filter isn't a product ID |
| 400 | `invalid_pagination` | `page` or `per_page` is below 1 |
| 401 | `invalid_api_key` | Missing, invalid or revoked key |
| 404 | `not_found` | No group with this ID in your store |
| 409 | `conflict` | The group was changed at the same time by someone else. Reload it and try again. |
| 422 | `no_product_ids` | `products` is missing or empty |
| 422 | `invalid_product_ids` | Some IDs aren't product IDs (see `details.invalid_product_ids`) |
| 422 | `already_grouped` | Some products are already in another group (see `details.already_grouped_product_ids`) |
| 422 | `no_products_found` | None of the products exist in your store |
| 422 | `cannot_unpublish` | `publish: false` on a published group |
| 429 | `rate_limited` | Too many requests, see [Rate limits](#rate-limits) |
| 502 | `shopify_unavailable` | Shopify couldn't be reached. Try again. |
