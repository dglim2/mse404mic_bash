#!/bin/bash

echo "Please enter a stock ticker or press Ctrl+C at any time to exit: "
while :; do
    # read ticker from user input while avoiding splitting and removing whitespace
    IFS= read -r ticker
    ticker="${ticker//[[:space:]]/}"
    
    # ensure ticker is not empty
    if [ -z "$ticker" ]; then
        echo "Ticker cannot be empty, please try again: "
        continue
    fi

    # find files matching ticker
    readarray -t matches < <(compgen -G "${ticker}"*)

    # count number of matches
    count=${#matches[@]}

    # retry if no matches found
    if [ $count -eq 0 ]; then
        echo "No files found starting with '$ticker', please try again: "
        continue
    fi

    # print matching files
    echo "Found $count matching file(s): "
    i=1
    for file in "${matches[@]}"; do
        echo "$i) $file "
        ((i++))
    done

    # file selection/confirmation loop
    echo "Please select/confirm a file by selecting a number: "
    while :; do
        # read choice from user input while avoiding splitting and removing whitespace
        IFS= read -r choice
        choice="${choice//[[:space:]]/}"

        # ensure choice is not empty
        if [ -z "$choice" ]; then
            echo "Choice cannot be empty, please try again: "
            continue
        fi
        
        # ensure choice is an integer and is in range
        if [[ $choice =~ ^[0-9]+$ ]] && ((choice>=1 && choice<=count)); then
            infile="${matches[choice-1]}"
            echo "Using: $infile"
            break
        else
            echo "Invalid input, please enter a number between 1 and $count: "
        fi
    done

    # time selection loop
    while :; do
        # month selection loop
        echo "Please enter a month by number, abbreviation, or full name: "
        while :; do
            # read month from user input while avoiding splitting and removing whitespace
            IFS= read -r month_raw
            month_raw="${month_raw//[[:space:]]/}"

            # ensure month is not empty
            if [ -z "$month_raw" ]; then
                echo "Month cannot be empty, please try again: "
                continue
            fi

            # change month to lowercase to avoid case sensitivity
            month_lowercase=$(echo "$month_raw" | tr '[:upper:]' '[:lower:]')

            # match month input
            case "$month_lowercase" in
                1|01|jan|january) month_num="01"; month_name="January" ;;
                2|02|feb|february) month_num="02"; month_name="February" ;;
                3|03|mar|march) month_num="03"; month_name="March" ;;
                4|04|apr|april) month_num="04"; month_name="April" ;;
                5|05|may) month_num="05"; month_name="May" ;;
                6|06|jun|june) month_num="06"; month_name="June" ;;
                7|07|jul|july) month_num="07"; month_name="July" ;;
                8|08|aug|august) month_num="08"; month_name="August" ;;
                9|09|sep|sept|september) month_num="09"; month_name="September" ;;
                10|oct|october) month_num="10"; month_name="October" ;;
                11|nov|november) month_num="11"; month_name="November" ;;
                12|dec|december) month_num="12"; month_name="December" ;;
                *) echo "Invalid month input, please try again: "; continue ;;
            esac
            break
        done

        # year selection loop
        echo "Please enter a 4-digit year: "
        while :; do
            # read year from user input while avoiding splitting and removing whitespace
            IFS= read -r year
            year="${year//[[:space:]]/}"

            # ensure year is not empty
            if [ -z "$year" ]; then
                echo "Year cannot be empty, please try again: "
                continue
            fi

            # ensure year is a 4-digit number
            if [[ "$year" =~ ^[0-9]{4}$ ]]; then
                break
            else
                echo "Invalid year, please enter a 4-digit year: "
            fi
        done

        # current time
        now_y=$(date +%Y)
        now_m=$(date +%m)

        # ensure selected time is not in the future
        if (( 10#$year > 10#$now_y )) || { (( 10#$year == 10#$now_y )) && (( 10#$month_num > 10#$now_m )); }; then
            echo "The selected time is in the future, please try again."
            continue
        fi

        break
    done

    # compute date window
    start="${year}-${month_num}-01"
    last_day=$(date -d "${start} +1 month -1 day" +%d)
    end="${year}-${month_num}-${last_day}"

    # create output file name
    ticker_upper=$(echo "$ticker" | tr '[:lower:]' '[:upper:]')
    outfile="${ticker_upper}_${month_name}_${year}.txt"

    # naively auto-detect delimiter by counting tabs and commas in first line
    header=$(head -n1 "$infile")
    commas=$(grep -o "," <<< "$header" | wc -l)
    tabs=$(grep -o $'\t' <<< "$header" | wc -l)

    # set delimiter to the more common between tabs and commas
    if (( tabs > commas )); then
        delim=$"\t"
    else
        delim=","
    fi

    # begin awk processing

    # create a temporary file for intermediate rows
    tmp_rows="$(mktemp)"

    # ensure temporary file is deleted on exit
    trap 'rm -f "$tmp_rows"' EXIT

    awk -F"$delim" -v start="$start" -v end="$end" '
        BEGIN {
            # map month abbreviation to numeric month values
            mon["Jan"]="01"; mon["Feb"]="02"; mon["Mar"]="03"; mon["Apr"]="04";
            mon["May"]="05"; mon["Jun"]="06"; mon["Jul"]="07"; mon["Aug"]="08";
            mon["Sep"]="09"; mon["Oct"]="10"; mon["Nov"]="11"; mon["Dec"]="12";
        }
        NR==1 {
            # locate column positions for Date and Adjusted Close
            for (i=1; i<=NF; i++) {
                h=$i; gsub(/\r/,"",h)
                if (h=="Date") dcol=i
                if (h ~ /^Adj Close/) acol=i
            }
            # if required columns are missing, exit with code 2
            if (!dcol || !acol) { exit 2 }
            next
        }
        # skip divident and stock split rows
        /Dividend|Split/ { next }
        {
            # clean carriage returns
            gsub(/\r/, "", $0)
            
            # skip if row is missing adjusted close
            if (NF < acol) next

            # adjusted closing price
            adj=$acol

            # raw date field
            raw=$dcol

            # remove commas
            gsub(",", "", raw)   # e.g., "Sep 06 2024"

            # split date into month, day, year
            split(raw, a, /[[:space:]]+/)
            if (length(a) < 3) next

            mm = mon[a[1]]; dd=a[2]; yy=a[3]

            # skip if month lookup fails
            if (mm=="") next

            # pad single digit days
            if (length(dd)==1) dd="0" dd

            # convert to YYYY-MM-DD format
            iso = sprintf("%04d-%02d-%02d", yy, mm, dd)

            # skip dates outside window
            if (iso < start || iso > end) next

            if (adj ~ /^[0-9.]+$/) {
                # convert dollars to cents
                cents = adj * 100

                # output as date + cents
                printf "%s\t%.0f\n", iso, cents
            }
        }
    ' "$infile" > "$tmp_rows"

    # save exit code for error handling
    awk_rc=$?

    # error handling
    if (( awk_rc == 2 )); then
        echo "Error: required columns not found in header (need Date and Adj Close)."
        rm -f "$tmp_rows"; trap - EXIT
        continue
    elif (( awk_rc != 0 )); then
        echo "An error occurred while processing '$infile' (awk exit code $awk_rc)."
        rm -f "$tmp_rows"; trap - EXIT
        continue
    fi

    # write output file in reverse chronological order
    {
        echo -e "Date\tAdjusted Closing Price / ¢"
        sort -r "$tmp_rows"
    } > "$outfile"

    # check if file only has header line (no data)
    lines=$(wc -l < "$outfile")
    if (( lines <= 1)); then
        echo "Warning: no trading data found for $month_name $year in '$infile'."
        echo "Created header-only (empty) file."
    fi

    rm -f "$tmp_rows"; trap - EXIT
    echo "Successfully wrote to '$outfile'."
    echo "--------------------------------------------------"
    echo "Application reset, please enter a new stock ticker or press Ctrl+C at any time to exit: "

    # we did it hooray :)
done