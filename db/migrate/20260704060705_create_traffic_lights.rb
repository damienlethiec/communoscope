class CreateTrafficLights < ActiveRecord::Migration[8.1]
  def change
    create_table :traffic_lights do |t|
      t.references :commune, null: false, foreign_key: true
      t.string :domaine, null: false
      t.string :couleur, null: false
      t.json :justification, null: false
      t.date :date, null: false

      t.timestamps
    end

    add_index :traffic_lights, [ :commune_id, :domaine ]
  end
end
