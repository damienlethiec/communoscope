class CreateMeasurements < ActiveRecord::Migration[8.1]
  def change
    create_table :measurements do |t|
      t.references :commune, null: false, foreign_key: true
      t.string :domaine, null: false
      t.string :indicateur, null: false
      t.decimal :valeur, null: false
      t.date :date, null: false
      t.string :source_url, null: false

      t.timestamps
    end

    add_index :measurements, [ :commune_id, :domaine, :indicateur, :date ],
      unique: true, name: "index_measurements_on_commune_domaine_indicateur_date"
    add_index :measurements, [ :domaine, :date ]
  end
end
