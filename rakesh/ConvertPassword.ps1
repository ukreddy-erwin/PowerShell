echo "-----------------------------------------------------------"
echo "Type the password you want to make secure and press enter"
echo "-----------------------------------------------------------"

read-host -assecurestring | convertfrom-securestring | Set-Clipboard

echo "-----------------------------------------------------------"
echo "content is copied to clipboard."
echo "-----------------------------------------------------------"
echo "Note: You can close this window now."
read-host