# Luxury weights: 2.5, 5.0, 6.25
# Herb weights, eggs, milk: 0.6
# Alchohol weights, meat, flour: 0.65
# Resource weights: 0.1*1.5^TIER

# TODO: add flour

# TODO: add luxury goods

function generate_items() :: Tuple{String, Dict{String, Float64}}
    list = ""
    weights = Dict{String, Float64}()

    for tier in 2:8
        # Add resource items
        for item in ["FIBER", "WOOD", "STONE", "ORE", "HIDE"]
            list *= "T$(tier)_$(item),"
            weight = 0.1 * 1.5^(tier)
            weights["T$(tier)_$(item)"] = weight

            if tier >= 4
                for enchantment in 1:4
                    name = "T$(tier)_$(item)_LEVEL$(enchantment)@$(enchantment)"
                    list *= "$(name),"
                    weights[name] = weight
                end
            end
        end
    end

    # Add farm produce items
    for item in ["T1_CARROT","T2_BEAN","T3_WHEAT","T4_TURNIP","T5_CABBAGE","T6_POTATO","T7_CORN","T8_PUMPKIN","T2_AGARIC","T3_COMFREY","T4_BURDOCK","T5_TEASEL","T6_FOXGLOVE","T7_MULLEIN","T8_YARROW","T3_EGG","T4_MILK","T5_EGG","T6_MILK","T8_MILK"]
        list *= "$(item),"
        weights[item] = 0.6
    end
    
    for item in ["T3_MEAT","T4_MEAT","T5_MEAT","T6_MEAT","T7_MEAT","T8_MEAT","T6_ALCOHOL","T7_ALCOHOL","T8_ALCOHOL"]
        list *= "$(item),"
        weights[item] = 0.65
    end
    
    for rarity in 1:3
        for type in ["KNOWLEDGE", "CEREMONIAL", "SILVERWARE", "DECORATIVE", "TRIBAL", "RITUAL"]
            item = "TREASURE_$(type)_RARITY$(rarity)"
            weight = rarity == 1 ? 2.5 : rarity == 2 ? 5.0 : 6.25
            
            list *= "$(item),"
            weights[item] = weight
        end
    end
    
    # Remove the trailing comma
    if endswith(list, ",")
        list::String = chop(list, tail=true)
    end

    # TODO: maybe function should return a vector of Strings, to avoid future splitting

    return list, weights
end

function generate_equipment_list()
    # TODO: for crafting and enchanting
    return "", Dict{String, Float64}()
end