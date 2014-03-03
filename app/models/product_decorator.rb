Spree::Product.class_eval do
  searchable do

    autocomplete :product_description, :using => :description
    autosuggest  :product_description, :using => :description
    autocomplete :product_name, :using => :name
    autosuggest  :product_name, :using => :name

    boolean :is_active, :using => :is_active?

    conf = Spree::Search::SpreeSunspot.configuration

    conf.fields.each do |field|
      if field.class == Hash
        field = { :opts => {} }.merge(field)

        if field[:opts][:block]
          block = field[:opts][:block]
          field[:opts].delete(:block)
          send field[:type], field[:name], field[:opts], &block
        else
          send field[:type], field[:name], field[:opts]
        end
      else
        text(field,:more_like_this => true)
      end
    end

    integer :site_id, :multiple => true do
      x = taxons.map {|t| t.taxonomy ? t.taxonomy.site_id : -1}
      x.flatten.uniq
    end

    # pull the product's taxon, and all its ancestors: this allows us to intersect the display with the current taxon's
    # children and allow the user to intuitively 'dig down' into the product heirarchy
    # root taxon is excluded: doesn't really allow for intuitive navigation
    integer :taxon_ids, :multiple => true, :references => Spree::Taxon do
      taxons.map { |t| t.self_and_ancestors.select { |tx| !tx.root? }.map(&:id) }.flatten(1).uniq
    end

    conf.option_facets.each do |option|
      string "#{option}_facet", :multiple => true do
        get_option_values(option.to_s).map(&:presentation)
      end
    end

    conf.property_facets.each do |prop|
      string "#{prop}_facet", :multiple => true do
        property(prop.to_s)
      end
    end

    conf.other_facets.each do |method|
      string "#{method}_facet", :multiple => true do
        send(method)
      end
    end

    if respond_to?(:stores)
      integer :store_ids, :multiple => true, :references => Store
    end

  end

  def is_active?
    !deleted_at && available_on &&
      (available_on <= Time.zone.now) #&&
        #(Spree::Config[:allow_backorders] || count_on_hand > 0)
  end

  def self.search_for(query, num_results = 10)
    Spree::Product.solr_search do
      fulltext query
      paginate :page => 1, :per_page => num_results
    end
  end

  def self.autocomplete(phrase, site_id, num_results = 10)
    Spree::Product.solr_search do
      with :site_id, site_id.to_i
      adjust_solr_params do |params|
        params[:q] = "product_name_ac:\"#{phrase}\""
      end
      paginate :page => 1, :per_page => num_results
    end
  end

  def self.autosuggest(phrase, site_id, num_results = 10)
    Spree::Product.solr_search do
      with :site_id, site_id.to_i
      adjust_solr_params do |params|
        params[:q] = "product_name_as:\"#{phrase}\""
      end
      paginate :page => 1, :per_page => num_results
    end
  end

  private

  def price_range
    max = 0
    Spree::Search::SpreeSunspot.configuration.price_ranges.each do |range, name|
      return name if range.include?(price)
      max = range.max if range.max > max
    end
    I18n.t(:price_and_above, :price => max)
  end

  def get_option_values(option_name)
    # in the next 1.1.x release this should be replaced with the option value accessors

    sql = <<-eos
      SELECT DISTINCT ov.id, ov.presentation
      FROM spree_option_values AS ov
      LEFT JOIN spree_option_types AS ot ON (ov.option_type_id = ot.id)
      LEFT JOIN spree_option_values_variants AS ovv ON (ovv.option_value_id = ov.id)
      LEFT JOIN spree_variants AS v ON (ovv.variant_id = v.id)
      LEFT JOIN spree_products AS p ON (v.product_id = p.id)
      WHERE (ot.name = '#{option_name}' AND p.id = #{self.id});
    eos
    Spree::OptionValue.find_by_sql(sql)
  end
end
