import json
import os
from datetime import datetime
from typing import Union

import requests
from loguru import logger

VERBOSE = int(os.getenv("VERBOSE", "0"))

logger.remove()
if VERBOSE:
    logger.add(
        sink=lambda msg: print(msg, end=""),
        format="<green>{time:YYYY-MM-DD HH:mm:ss}</green> | <level>{level}</level> | <cyan>{message}</cyan>",
        level="INFO",
    )


class SimpleWeatherAgent:
    def __init__(self, tgi_endpoint: str):
        self.tgi_endpoint = tgi_endpoint
        self.base_url = "https://api.open-meteo.com/v1/forecast"
        self.geocode_url = "https://nominatim.openstreetmap.org/search"
        logger.info("SimpleWeatherAgent initialized.")

    def get_coordinates(self, city: str) -> tuple:
        logger.debug(f"Fetching coordinates for city: {city}")
        params = {"q": city, "format": "json", "limit": 1}
        response = requests.get(self.geocode_url, params=params)
        if response.status_code != 200:
            logger.error(
                f"Failed to fetch coordinates. HTTP Status: {response.status_code}"
            )
            raise ValueError(f"Failed to fetch coordinates for {city}")
        data = response.json()
        logger.debug(f"Geocode response: {json.dumps(data, indent=2)}")
        if not data:
            logger.error(f"Could not find coordinates for {city}")
            raise ValueError(f"Could not find coordinates for {city}")
        lat, lon = float(data[0]["lat"]), float(data[0]["lon"])
        logger.info(f"Coordinates for {city}: lat={lat}, lon={lon}")
        return lat, lon

    def get_weather(self, city: str) -> dict:
        try:
            logger.info(f"Fetching weather for city: {city}")
            lat, lon = self.get_coordinates(city)
            params = {
                "latitude": lat,
                "longitude": lon,
                "current_weather": True,
                "timezone": "auto",
            }
            response = requests.get(self.base_url, params=params)
            if response.status_code != 200:
                logger.error(
                    f"Failed to fetch weather data. HTTP Status: {response.status_code}"
                )
                raise ValueError(f"Failed to fetch weather data for {city}")
            data = response.json()
            logger.debug(f"Weather response: {json.dumps(data, indent=2)}")
            weather = data["current_weather"]
            temp = weather["temperature"]
            comfort = (
                "very cold"
                if temp < 0
                else (
                    "cold"
                    if temp < 15
                    else "comfortable" if temp < 25 else "warm" if temp < 30 else "hot"
                )
            )
            result = {
                "city": city,
                "temperature": temp,
                "wind_speed": weather["windspeed"],
                "comfort": comfort,
                "timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
            }
            logger.info(f"Weather for {city}: {json.dumps(result, indent=2)}")
            return result
        except Exception as e:
            logger.error(f"Error while fetching weather: {str(e)}")
            return {"error": str(e)}

    def query_tgi(self, prompt: str, expect_json: bool = True) -> Union[dict, str]:
        logger.info("Querying the LLM via TGI server.")
        payload = {
            "inputs": prompt,
            "parameters": {"max_new_tokens": 200, "temperature": 0.7, "stop": ["\n\n"]},
        }
        response = requests.post(self.tgi_endpoint, json=payload)
        if response.status_code != 200:
            logger.error(
                f"TGI server query failed. HTTP Status: {response.status_code}"
            )
            raise ValueError("Failed to query TGI server.")
        data = response.json()
        generated_text = data.get("generated_text", "")
        logger.debug(f"TGI raw response: {generated_text}")
        if expect_json:
            try:
                start = generated_text.find("{")
                end = generated_text.rfind("}") + 1
                if start >= 0 and end > start:
                    json_str = generated_text[start:end]
                    return json.loads(json_str)
                else:
                    raise ValueError("No valid JSON found in response")
            except json.JSONDecodeError as e:
                logger.error(f"Failed to parse JSON from response: {e}")
                raise ValueError(f"Invalid JSON in response: {generated_text}")
        else:
            return generated_text.strip()

    def execute_plan(self, plan: dict) -> dict:
        try:
            action = plan.get("action")
            if action == "get_weather":
                city = plan["parameters"]["city"]
                return self.get_weather(city)
            else:
                logger.error(f"Unknown action: {action}")
                return {"error": f"Unknown action: {action}"}
        except Exception as e:
            logger.error(f"Error while executing plan: {str(e)}")
            return {"error": str(e)}


def main():
    tgi_endpoint = "http://localhost:8080/generate"
    agent = SimpleWeatherAgent(tgi_endpoint)
    print("Weather AI Agent (type 'quit' to exit)")
    while True:
        user_input = input("\nUser: ").strip()
        if user_input.lower() == "quit":
            logger.info("Exiting AI Agent.")
            break
        planning_prompt = f"""You are an AI assistant. Based on the user's input, plan an action.
            Your response must be a valid JSON object with exactly this structure:
            {{
                "action": "get_weather",
                "parameters": {{
                    "city": "<city_name>"
                }}
            }}
            User input: {user_input}
        Response:"""
        try:
            plan = agent.query_tgi(planning_prompt, expect_json=True)
            logger.info(f"Generated plan: {json.dumps(plan, indent=2)}")
            result = agent.execute_plan(plan)
            response_prompt = f"""Based on this weather data, create a friendly and informative response for the user.
            Include the temperature, comfort level, and wind conditions in a conversational way.
            Keep the response concise but engaging.
            Weather data: {json.dumps(result, indent=2)}
            Response:"""
            natural_response = agent.query_tgi(response_prompt, expect_json=False)
            logger.info(json.dumps(result, indent=2))
            print(natural_response)
        except Exception as e:
            logger.error(f"Error in agent workflow: {str(e)}")
            print("\nAgent Response:")
            print(json.dumps({"error": str(e)}, indent=2))


if __name__ == "__main__":
    main()
