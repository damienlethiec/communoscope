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

ActiveRecord::Schema[8.1].define(version: 2026_07_04_060705) do
  create_table "communes", force: :cascade do |t|
    t.string "code_insee", null: false
    t.datetime "created_at", null: false
    t.string "nom", null: false
    t.integer "population"
    t.datetime "updated_at", null: false
    t.index ["code_insee"], name: "index_communes_on_code_insee", unique: true
  end

  create_table "measurements", force: :cascade do |t|
    t.integer "commune_id", null: false
    t.datetime "created_at", null: false
    t.date "date", null: false
    t.string "domaine", null: false
    t.string "indicateur", null: false
    t.string "source_url", null: false
    t.datetime "updated_at", null: false
    t.decimal "valeur", null: false
    t.index ["commune_id", "domaine", "indicateur", "date"], name: "index_measurements_on_commune_domaine_indicateur_date", unique: true
    t.index ["commune_id"], name: "index_measurements_on_commune_id"
    t.index ["domaine", "date"], name: "index_measurements_on_domaine_and_date"
  end

  create_table "traffic_lights", force: :cascade do |t|
    t.integer "commune_id", null: false
    t.string "couleur", null: false
    t.datetime "created_at", null: false
    t.date "date", null: false
    t.string "domaine", null: false
    t.json "justification", null: false
    t.datetime "updated_at", null: false
    t.index ["commune_id", "domaine"], name: "index_traffic_lights_on_commune_id_and_domaine"
    t.index ["commune_id"], name: "index_traffic_lights_on_commune_id"
  end

  add_foreign_key "measurements", "communes"
  add_foreign_key "traffic_lights", "communes"
end
