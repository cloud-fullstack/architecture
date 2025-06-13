# Consolidate all charts into k3s/charts directory

# Define source and destination directories
$sourceCharts = "charts"
$destCharts = "k3s/charts"

# Create destination directory if it doesn't exist
if (-not (Test-Path $destCharts)) {
    New-Item -ItemType Directory -Path $destCharts -Force
}

# Copy chatbot services
Write-Host "Copying chatbot services..."
Copy-Item -Path "$sourceCharts/chatbot-services" -Destination "$destCharts/chatbot" -Recurse -Force

# Copy omero-api
Write-Host "Copying omero-api..."
Copy-Item -Path "$sourceCharts/omero-api" -Destination "$destCharts/omero-api" -Recurse -Force

# Move existing k3s charts to new location
Write-Host "Moving k3s charts..."
$existingCharts = Get-ChildItem "k3s/charts" -Directory
foreach ($chart in $existingCharts) {
    $newPath = Join-Path $destCharts $chart.Name
    if (-not (Test-Path $newPath)) {
        Move-Item -Path $chart.FullName -Destination $newPath -Force
    }
}

# Remove empty source directories
Write-Host "Cleaning up..."
Remove-Item -Path "$sourceCharts" -Recurse -Force

Write-Host "Consolidation complete! All charts are now in $destCharts"
