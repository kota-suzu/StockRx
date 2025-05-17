json.array! @inventories do |inventory|
  json.id inventory.id
  json.name inventory.name
  json.quantity inventory.quantity
  json.price inventory.price
  json.formatted_price inventory.formatted_price
  json.status inventory.status
  json.alert_status inventory.quantity <= 0 ? "low" : "ok"
  json.updated_at inventory.updated_at
  json.batches inventory.batches do |batch|
    json.id batch.id
    json.lot_code batch.lot_code
    json.quantity batch.quantity
    json.expires_on batch.expires_on
    json.expired batch.expired?
  end
end
