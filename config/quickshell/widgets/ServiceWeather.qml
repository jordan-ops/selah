pragma Singleton
import QtQuick
import Quickshell
import "../services" as Services

// Adapter for the ported Nebula widgets (Nebula shell, GPL-3.0): answers
// the member names the widget files bind on, backed by this shell's
// services/Weather.qml — one wttr.in fetch serves the bar chip AND these
// widgets (forecast days, hourly slots, astronomy incl. moonrise/set and
// phase all come from the same j1 payload). Upstream's Python CLI is gone;
// the hourly bucketing, night detection and the wttr-code → Material icon
// map are copied verbatim because widgets render their output directly.
//
// weather.location from SettingsConfig is display-only here: our fetch
// pins to wttr.in auto-IP (Settings ▸ doesn't ship a city override).
Singleton {
    id: root

    // ── raw payload slices (reactive on services/Weather.raw) ────────
    readonly property var currentCondition: {
        const r = Services.Weather.raw
        return (r && r.current_condition && r.current_condition.length > 0)
            ? r.current_condition[0] : null
    }
    readonly property var locationData: {
        const r = Services.Weather.raw
        return (r && r.nearest_area && r.nearest_area.length > 0) ? r.nearest_area[0] : null
    }
    readonly property var astronomy: {
        const r = Services.Weather.raw
        if (r && r.weather && r.weather[0] && r.weather[0].astronomy)
            return r.weather[0].astronomy[0]
        return null
    }
    readonly property var forecastDays: {
        const r = Services.Weather.raw
        return (r && r.weather && r.weather.length > 0) ? r.weather : []
    }
    readonly property var hourlyForecast: {
        const d = root.forecastDays
        return d.length > 0 ? d[0].hourly : []
    }

    // ── upstream state surface ───────────────────────────────────────
    property string location: SettingsConfig.weather.location
    property bool useMetric: SettingsConfig.weather.useMetric ?? true
    property int refreshInterval: (SettingsConfig.weather.refreshInterval ?? 15) * 60000
    readonly property bool isLoading: Services.Weather.fetching
    readonly property bool hasError: Services.Weather.hasError
    readonly property var lastUpdated: Services.Weather.lastUpdated

    // ── convenient properties (verbatim) ─────────────────────────────
    readonly property string temperature: root.currentCondition
        ? (useMetric ? root.currentCondition.temp_C + "°" : root.currentCondition.temp_F + "°") : "0°"
    readonly property string feelsLike: root.currentCondition
        ? (useMetric ? root.currentCondition.FeelsLikeC + "°" : root.currentCondition.FeelsLikeF + "°") : "N/A"
    readonly property real humidity: root.currentCondition ? root.currentCondition.humidity : 0
    readonly property string description:
        root.currentCondition ? root.currentCondition.weatherDesc[0].value : "No data"
    readonly property string weatherCode: root.currentCondition ? root.currentCondition.weatherCode : "113"
    readonly property string cityName:
        root.locationData ? root.locationData.areaName[0].value : "Unknown"
    readonly property string windSpeed:
        root.currentCondition ? root.currentCondition.windspeedKmph + " km/h" : "N/A"
    readonly property real windDegree: root.currentCondition ? root.currentCondition.winddirDegree : 0
    readonly property string windDirection:
        root.currentCondition ? root.currentCondition.winddir16Point : "N/A"
    readonly property string cloudcover:
        root.currentCondition ? root.currentCondition.cloudcover + "%" : "N/A"
    readonly property string uvindex: root.currentCondition ? root.currentCondition.uvIndex : "N/A"
    readonly property string visibility: root.currentCondition ? root.currentCondition.visibility : "N/A"
    readonly property string precipitation:
        root.currentCondition ? root.currentCondition.precipInches : "N/A"
    readonly property real currentPressure:
        root.currentCondition ? root.currentCondition.pressure : root.min_pressure
    readonly property string pressureInches:
        root.currentCondition ? root.currentCondition.pressureInches : "N/A"

    readonly property real min_pressure: 960
    readonly property real max_pressure: 1060

    // progress 0.0 → 1.0
    readonly property real pressure:
        (root.currentPressure - root.min_pressure) / (root.max_pressure - root.min_pressure)

    function mapHourly(h) {
        return {
            time:          formatHourlyTime(h.time),
            tempC:         h.tempC + "°",
            tempF:         h.tempF + "°",
            feelsLikeC:    h.FeelsLikeC + "°",
            feelsLikeF:    h.FeelsLikeF + "°",
            humidity:      h.humidity,
            weatherCode:   h.weatherCode,
            description:   h.weatherDesc[0].value.trim(),
            chanceofrain:  h.chanceofrain,
            windspeedKmph: h.windspeedKmph,
            uvIndex:       h.uvIndex
        }
    }

    function getHourlyForDay(dayIndex) {
        if (!root.forecastDays || root.forecastDays.length <= dayIndex) return []
        const day = root.forecastDays[dayIndex]
        if (!day || !day.hourly) return []

        const now = new Date()
        const currentTotalMinutes = now.getHours() * 60 + now.getMinutes()

        const filtered = day.hourly
            .filter(h => {
                const hours = Math.floor(parseInt(h.time) / 100)
                return dayIndex > 0 || (hours * 60) >= currentTotalMinutes
            })
            .map(mapHourly)

        if (dayIndex === 0 && root.currentCondition) {
            const cur = root.currentCondition
            const current = {
                time:          "Now",
                tempC:         cur.temp_C + "°",
                tempF:         cur.temp_F + "°",
                feelsLikeC:    cur.FeelsLikeC + "°",
                feelsLikeF:    cur.FeelsLikeF + "°",
                humidity:      cur.humidity,
                weatherCode:   cur.weatherCode,
                description:   cur.weatherDesc[0].value.trim(),
                chanceofrain:  cur.chanceofrain ?? "0",
                windspeedKmph: cur.windspeedKmph,
                uvIndex:       cur.uvIndex
            }

            const combined = [current].concat(filtered)

            if (combined.length < 8 && root.forecastDays.length > 1) {
                const nextDay = root.forecastDays[1]
                if (nextDay && nextDay.hourly) {
                    const needed = 8 - combined.length
                    return combined.concat(nextDay.hourly.slice(0, needed).map(mapHourly))
                }
            }
            return combined
        }

        // For dayIndex > 0, pad from next day if under 8
        if (filtered.length < 8 && root.forecastDays.length > dayIndex + 1) {
            const nextDay = root.forecastDays[dayIndex + 1]
            if (nextDay && nextDay.hourly) {
                const needed = 8 - filtered.length
                return filtered.concat(nextDay.hourly.slice(0, needed).map(mapHourly))
            }
        }
        return filtered
    }

    // wttr "time" field (0, 300, 600 … 2100) → "12 AM"
    function formatHourlyTime(timeVal) {
        const t = parseInt(timeVal)
        const hours = Math.floor(t / 100)
        const ampm = hours >= 12 ? "PM" : "AM"
        const h12 = hours % 12 === 0 ? 12 : hours % 12
        return h12 + " " + ampm
    }

    readonly property var todayHourly: getHourlyForDay(0)
    readonly property var tomorrowHourly: getHourlyForDay(1)

    function refresh() { Services.Weather.refresh() }

    function isNightTime() {
        const astro = root.astronomy
        if (!astro || !astro.sunrise || !astro.sunset) {
            const hour = new Date().getHours()
            return hour < 6 || hour >= 18
        }

        const now = new Date()
        const currentTime = now.getHours() * 60 + now.getMinutes()

        function parseTime(str) {
            const m = str.match(/(\d{1,2}):(\d{2})\s*(AM|PM)/i)
            if (!m) return null
            let h = parseInt(m[1])
            const min = parseInt(m[2])
            const ap = m[3].toUpperCase()
            if (ap === "PM" && h !== 12) h += 12
            if (ap === "AM" && h === 12) h = 0
            return h * 60 + min
        }

        const sunriseTime = parseTime(astro.sunrise)
        const sunsetTime  = parseTime(astro.sunset)

        if (sunriseTime === null || sunsetTime === null) {
            const hour = now.getHours()
            return hour < 6 || hour >= 18
        }

        return currentTime < sunriseTime || currentTime >= sunsetTime
    }

    function getWeatherIcon(code, night) {
        const isNight = night ?? isNightTime()

        const dayIconMap = {
            "113": { icon: "clear_day",           svg: "sunny" },
            "116": { icon: "partly_cloudy_day",   svg: "sunny_with_cloudy" },
            "119": { icon: "cloud",               svg: "cloudy" },
            "122": { icon: "cloud",               svg: "cloudy" },
            "143": { icon: "foggy",               svg: "cloudy" },
            "176": { icon: "rainy_light",         svg: "cloudy_with_rain" },
            "179": { icon: "weather_snowy",       svg: "cloudy_with_snow" },
            "182": { icon: "cloudy_snowing",      svg: "rain_with_snow" },
            "185": { icon: "cloudy_snowing",      svg: "rain_with_snow" },
            "200": { icon: "thunderstorm",        svg: "thunderstorms" },
            "227": { icon: "weather_snowy",       svg: "blowing_snow" },
            "230": { icon: "weather_snowy",       svg: "blizzard" },
            "248": { icon: "foggy",               svg: "cloudy" },
            "260": { icon: "foggy",               svg: "cloudy" },
            "263": { icon: "grain",               svg: "drizzle" },
            "266": { icon: "grain",               svg: "drizzle" },
            "281": { icon: "grain",               svg: "drizzle" },
            "284": { icon: "rainy",               svg: "cloudy_with_rain" },
            "293": { icon: "rainy_light",         svg: "cloudy_with_rain" },
            "296": { icon: "rainy_light",         svg: "cloudy_with_rain" },
            "299": { icon: "rainy",               svg: "rain_with_cloudy" },
            "302": { icon: "rainy",               svg: "rain_with_cloudy" },
            "305": { icon: "rainy_heavy",         svg: "heavy_rain" },
            "308": { icon: "rainy_heavy",         svg: "heavy_rain" },
            "311": { icon: "cloudy_snowing",      svg: "sleet_hail" },
            "314": { icon: "cloudy_snowing",      svg: "sleet_hail" },
            "317": { icon: "cloudy_snowing",      svg: "rain_with_snow" },
            "320": { icon: "cloudy_snowing",      svg: "rain_with_snow" },
            "323": { icon: "weather_snowy",       svg: "cloudy_with_snow" },
            "326": { icon: "weather_snowy",       svg: "cloudy_with_snow" },
            "329": { icon: "weather_snowy",       svg: "heavy_snow" },
            "332": { icon: "weather_snowy",       svg: "heavy_snow" },
            "335": { icon: "ac_unit",             svg: "blizzard" },
            "338": { icon: "ac_unit",             svg: "blizzard" },
            "350": { icon: "ac_unit",             svg: "sleet_hail" },
            "353": { icon: "rainy_light",         svg: "drizzle" },
            "356": { icon: "rainy",               svg: "rain_with_cloudy" },
            "359": { icon: "rainy_heavy",         svg: "rain_with_cloudy" },
            "362": { icon: "cloudy_snowing",      svg: "rain_with_snow" },
            "365": { icon: "cloudy_snowing",      svg: "rain_with_snow" },
            "368": { icon: "weather_snowy",       svg: "flurries" },
            "371": { icon: "ac_unit",             svg: "heavy_snow" },
            "374": { icon: "ac_unit",             svg: "sleet_hail" },
            "377": { icon: "ac_unit",             svg: "sleet_hail" },
            "386": { icon: "thunderstorm",        svg: "strong_thunderstorms" },
            "389": { icon: "thunderstorm",        svg: "strong_thunderstorms" },
            "392": { icon: "thunderstorm",        svg: "thunderstorms" },
            "395": { icon: "thunderstorm",        svg: "blizzard" }
        }

        const nightIconMap = {
            "113": { icon: "clear_night",           svg: "clear_night" },
            "116": { icon: "partly_cloudy_night",   svg: "cloudy_with_sunny" },
            "119": { icon: "cloud",                 svg: "cloudy" },
            "122": { icon: "cloud",                 svg: "cloudy" },
            "143": { icon: "foggy",                 svg: "cloudy" },
            "176": { icon: "rainy_light",           svg: "cloudy_with_rain" },
            "179": { icon: "weather_snowy",         svg: "cloudy_with_snow" },
            "182": { icon: "cloudy_snowing",        svg: "rain_with_snow" },
            "185": { icon: "cloudy_snowing",        svg: "rain_with_snow" },
            "200": { icon: "thunderstorm",          svg: "thunderstorms" },
            "227": { icon: "weather_snowy",         svg: "blowing_snow" },
            "230": { icon: "weather_snowy",         svg: "blizzard" },
            "248": { icon: "foggy",                 svg: "cloudy" },
            "260": { icon: "foggy",                 svg: "cloudy" },
            "263": { icon: "grain",                 svg: "drizzle" },
            "266": { icon: "grain",                 svg: "drizzle" },
            "281": { icon: "grain",                 svg: "drizzle" },
            "284": { icon: "rainy",                 svg: "cloudy_with_rain" },
            "293": { icon: "rainy_light",           svg: "cloudy_with_rain" },
            "296": { icon: "rainy_light",           svg: "cloudy_with_rain" },
            "299": { icon: "rainy",                 svg: "rain_with_cloudy" },
            "302": { icon: "rainy",                 svg: "rain_with_cloudy" },
            "305": { icon: "rainy_heavy",           svg: "rain_with_cloudy" },
            "308": { icon: "rainy_heavy",           svg: "rain_with_cloudy" },
            "311": { icon: "cloudy_snowing",        svg: "sleet_hail" },
            "314": { icon: "cloudy_snowing",        svg: "sleet_hail" },
            "317": { icon: "cloudy_snowing",        svg: "rain_with_snow" },
            "320": { icon: "cloudy_snowing",        svg: "rain_with_snow" },
            "323": { icon: "weather_snowy",         svg: "cloudy_with_snow" },
            "326": { icon: "weather_snowy",         svg: "cloudy_with_snow" },
            "329": { icon: "weather_snowy",         svg: "heavy_snow" },
            "332": { icon: "weather_snowy",         svg: "heavy_snow" },
            "335": { icon: "ac_unit",               svg: "blizzard" },
            "338": { icon: "ac_unit",               svg: "blizzard" },
            "350": { icon: "ac_unit",               svg: "sleet_hail" },
            "353": { icon: "rainy_light",           svg: "drizzle" },
            "356": { icon: "rainy",                 svg: "rain_with_cloudy" },
            "359": { icon: "rainy_heavy",           svg: "rain_with_cloudy" },
            "362": { icon: "cloudy_snowing",        svg: "rain_with_snow" },
            "365": { icon: "cloudy_snowing",        svg: "rain_with_snow" },
            "368": { icon: "weather_snowy",         svg: "flurries" },
            "371": { icon: "ac_unit",               svg: "heavy_snow" },
            "374": { icon: "ac_unit",               svg: "sleet_hail" },
            "377": { icon: "ac_unit",               svg: "sleet_hail" },
            "386": { icon: "thunderstorm",          svg: "strong_thunderstorms" },
            "389": { icon: "thunderstorm",          svg: "strong_thunderstorms" },
            "392": { icon: "thunderstorm",          svg: "thunderstorms" },
            "395": { icon: "thunderstorm",          svg: "blizzard" }
        }

        const iconMap = isNight ? nightIconMap : dayIconMap
        return iconMap[code] || (isNight
            ? { icon: "clear_night", svg: "clear_night" }
            : { icon: "clear_day",   svg: "sunny" }
        )
    }

    readonly property var weatherIconPath: getWeatherIcon(root.weatherCode)
}
