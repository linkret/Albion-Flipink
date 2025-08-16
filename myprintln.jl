using Printf

# Custom print function that shows floats with all decimals instead of scientific notation
# It's otherwise identical to the default println() and implemented through Base.println

function myprintln()
    println()
    return
end

function myprintln(io::IO)
    println(io)
    return
end

function myprintln(x::Float64, xs...)
    @printf("%.2f", x)
    myprintln(xs...)
end

function myprintln(io::IO, x::Float64, xs...)
    @printf(io, "%.2f", x)
    myprintln(io, xs...)
end

function myprintln(x, xs...)
    print(x)
    myprintln(xs...)
end

function myprintln(io::IO, x, xs...)
    print(io, x)
    myprintln(io, xs...)
end