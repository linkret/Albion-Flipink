using HTTP
using JSON
using Statistics

include("item_list.jl")  # this file contains the generate_item_list function

function calculate_avg_volume(data)
    # Calculate the average volume from the historical data
    if isempty(data)
        return 0.0
    end

    # TODO: only look at last 1 week of historic data?

    volumes = [item["item_count"] for item in data if haskey(item, "item_count")]
    
    if isempty(volumes)
        return 0.0
    end

    return mean(volumes)
end

function fetch_data(itemList::String, locations::String)
    format = "json"
    api_base_url = "https://europe.albion-online-data.com"

    # API endpoint for fetching prices
    price_endpoint = "/api/v2/stats/Prices/$(itemList).$(format)?locations=$(locations)"
    # For historical data, to approximate the volume we can buy and sell
    time_scale = "24" # 24 hours - daily trading
    historic_endpoint = "/api/v2/stats/History/$(itemList).$(format)?locations=$(locations)&time-scale=$(time_scale)"

    price_url = "$(api_base_url)$(price_endpoint)"
    historic_url = "$(api_base_url)$(historic_endpoint)"

    response = HTTP.get(price_url)
    price_data = JSON.parse(String(response.body))

    # Filter the data to include only specific fields
    price_data = [
        Dict(
            "item_id" => item["item_id"],
            # "quality" => item["quality"], # Would only be useful for equipment items, which we probably won't use
            "price" => item["sell_price_min"],
            "city" => item["city"]
        )
        for item in price_data
    ]
    
    # Filter out items with a price of 0
    price_data = filter(item -> item["price"] != 0, price_data)

    # Transform the data to be accesed as price[city][item_id]
    transformed_data = Dict{String, Dict{String, Float64}}()

    for item in price_data
        city = item["city"]
        item_id = item["item_id"]
        price = item["price"]

        if !haskey(transformed_data, city)
            transformed_data[city] = Dict{String, Float64}()
        end

        transformed_data[city][item_id] = price
    end

    price_data = copy(transformed_data)
                
    # Print the price_data
    # println("Prices:\n", price_data)

    # Fetch historical data if needed
    historic_response = HTTP.get(historic_url)
    historic_data = JSON.parse(String(historic_response.body))

    # println("Historic data:\n", historic_data)

    # Filter the data to include only specific fields
    historic_data = [
        Dict(
            "item_id" => item["item_id"],
            # "quality" => item["quality"], # Would only be useful for equipment items, which we probably won't use
            "city" => item["location"],
            "avg_volume" => calculate_avg_volume(item["data"])
        )
        for item in historic_data
    ]

    # Filter out items with an average volume of 0
    historic_data = filter(item -> item["avg_volume"] != 0, historic_data)

    transformed_data = Dict{String, Dict{String, Float64}}()

    for item in historic_data
        item_id = item["item_id"]
        city = item["city"]
        avg_volume = item["avg_volume"]

        if !haskey(transformed_data, city)
            transformed_data[city] = Dict{String, Float64}()
        end

        transformed_data[city][item_id] = avg_volume
    end

    historic_data = copy(transformed_data)

    # Print the historical data
    # println("Volumes:\n", historic_data)

    return price_data, historic_data
end

function write_data_to_files()
    itemList, weights = generate_item_list()
    # itemList = "T2_FIBER,T3_FIBER,T4_FIBER,T4_FIBER_LEVEL1@1" #TODO: add more items to trade
    # TODO: dont hardcore locations
    locations = "Thetford,Lymhurst,Fort%20Sterling" # %20 is a space used in URLs
    price_data, historic_data = fetch_data(itemList, locations)

    if length(price_data) != length(historic_data)
        error("Price data and historic data have different lengths!")
    end

    # save data to files
    open("prices.json", "w") do file
        JSON.print(file, price_data, 2)
    end

    open("volumes.json", "w") do file
        JSON.print(file, historic_data, 2)
    end

    return price_data, historic_data
end

function read_data_from_files()
    # Read the data from the files
    price_data = JSON.parsefile("prices.json")
    historic_data = JSON.parsefile("volumes.json")

    # Print the data
    println("Prices:\n", price_data)
    println("Volumes:\n", historic_data)

    return price_data, historic_data
end

# write_data_to_files()
# read_data_from_files()