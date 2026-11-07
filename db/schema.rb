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

ActiveRecord::Schema[8.1].define(version: 2026_11_07_010100) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "players", force: :cascade do |t|
    t.bigint "room_id", null: false
    t.string "browser_token", null: false
    t.string "nickname", null: false
    t.datetime "joined_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
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
    t.index ["code"], name: "index_rooms_on_code_live", unique: true, where: "(expired_at IS NULL)"
  end

  add_foreign_key "players", "rooms"
  add_foreign_key "rooms", "players", column: "host_player_id"
end
