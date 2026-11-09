# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_11_10_120000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_db_files", force: :cascade do |t|
    t.string "ref", null: false
    t.binary "data", null: false
    t.datetime "created_at", null: false
    t.index ["ref"], name: "index_active_storage_db_files_on_ref", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "game_players", force: :cascade do |t|
    t.bigint "game_id", null: false
    t.bigint "player_id"
    t.string "nickname", null: false
    t.integer "total", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "buddies_left", default: 2, null: false
    t.index ["game_id"], name: "index_game_players_on_game_id"
    t.index ["player_id"], name: "index_game_players_on_player_id"
  end

  create_table "games", force: :cascade do |t|
    t.bigint "room_id", null: false
    t.string "recap_token", null: false
    t.string "status", default: "in_progress", null: false
    t.datetime "finished_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["recap_token"], name: "index_games_on_recap_token", unique: true
    t.index ["room_id"], name: "index_games_on_room_id"
  end

  create_table "hands", force: :cascade do |t|
    t.bigint "round_id", null: false
    t.bigint "game_player_id", null: false
    t.integer "template_ids", default: [], null: false, array: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["game_player_id"], name: "index_hands_on_game_player_id"
    t.index ["round_id", "game_player_id"], name: "index_hands_on_round_id_and_game_player_id", unique: true
    t.index ["round_id"], name: "index_hands_on_round_id"
  end

  create_table "memes", force: :cascade do |t|
    t.bigint "round_id", null: false
    t.bigint "game_player_id", null: false
    t.bigint "template_id"
    t.jsonb "caption_texts", default: [], null: false
    t.integer "position"
    t.integer "points", default: 0, null: false
    t.integer "up_count", default: 0, null: false
    t.integer "meh_count", default: 0, null: false
    t.integer "down_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["game_player_id"], name: "index_memes_on_game_player_id"
    t.index ["round_id", "game_player_id"], name: "index_memes_on_round_id_and_game_player_id", unique: true
    t.index ["round_id"], name: "index_memes_on_round_id"
    t.index ["template_id"], name: "index_memes_on_template_id"
  end

  create_table "packs", force: :cascade do |t|
    t.string "name", null: false
    t.boolean "custom", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index "lower((name)::text)", name: "index_packs_on_lower_name", unique: true
    t.index ["custom"], name: "index_packs_on_single_custom", unique: true, where: "custom"
  end

  create_table "players", force: :cascade do |t|
    t.bigint "room_id", null: false
    t.string "browser_token", null: false
    t.string "nickname", null: false
    t.datetime "joined_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "connections_count", default: 0, null: false
    t.integer "presence_token", default: 0, null: false
    t.datetime "away_at"
    t.index "room_id, lower((nickname)::text)", name: "index_players_on_room_id_and_lower_nickname", unique: true
    t.index ["room_id", "browser_token"], name: "index_players_on_room_id_and_browser_token", unique: true
    t.index ["room_id"], name: "index_players_on_room_id"
  end

  create_table "rooms", force: :cascade do |t|
    t.string "code", null: false
    t.bigint "host_player_id"
    t.string "phase", default: "waiting", null: false
    t.integer "phase_seq", default: 0, null: false
    t.datetime "phase_deadline_at"
    t.datetime "last_activity_at", null: false
    t.datetime "expired_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "current_game_id"
    t.integer "current_round_number"
    t.bigint "current_meme_id"
    t.bigint "off_pack_ids", default: [], null: false, array: true
    t.boolean "upload_grace_used", default: false, null: false
    t.string "captioning_preset", default: "normal", null: false
    t.index ["code"], name: "index_rooms_on_code_live", unique: true, where: "(expired_at IS NULL)"
    t.index ["current_game_id"], name: "index_rooms_on_current_game_id"
    t.index ["current_meme_id"], name: "index_rooms_on_current_meme_id"
  end

  create_table "rounds", force: :cascade do |t|
    t.bigint "game_id", null: false
    t.integer "number", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["game_id", "number"], name: "index_rounds_on_game_id_and_number", unique: true
    t.index ["game_id"], name: "index_rounds_on_game_id"
  end

  create_table "template_tombstones", force: :cascade do |t|
    t.string "memegen_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["memegen_id"], name: "index_template_tombstones_on_memegen_id", unique: true
  end

  create_table "templates", force: :cascade do |t|
    t.string "memegen_id", null: false
    t.string "name", null: false
    t.string "source"
    t.jsonb "text_boxes", default: [], null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "pack_id", null: false
    t.string "source_kind", default: "memegen", null: false
    t.datetime "reviewed_at"
    t.datetime "hidden_at"
    t.index ["memegen_id"], name: "index_templates_on_memegen_id", unique: true
    t.index ["pack_id"], name: "index_templates_on_pack_id"
  end

  create_table "votes", force: :cascade do |t|
    t.bigint "meme_id", null: false
    t.bigint "game_player_id", null: false
    t.string "kind", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["game_player_id"], name: "index_votes_on_game_player_id"
    t.index ["meme_id", "game_player_id"], name: "index_votes_on_meme_id_and_game_player_id", unique: true
    t.index ["meme_id"], name: "index_votes_on_meme_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "game_players", "games"
  add_foreign_key "game_players", "players", on_delete: :nullify
  add_foreign_key "games", "rooms"
  add_foreign_key "hands", "game_players"
  add_foreign_key "hands", "rounds"
  add_foreign_key "memes", "game_players"
  add_foreign_key "memes", "rounds"
  add_foreign_key "memes", "templates", on_delete: :nullify
  add_foreign_key "players", "rooms"
  add_foreign_key "rooms", "games", column: "current_game_id"
  add_foreign_key "rooms", "memes", column: "current_meme_id", on_delete: :nullify
  add_foreign_key "rooms", "players", column: "host_player_id"
  add_foreign_key "rounds", "games"
  add_foreign_key "templates", "packs"
  add_foreign_key "votes", "game_players"
  add_foreign_key "votes", "memes"
end
