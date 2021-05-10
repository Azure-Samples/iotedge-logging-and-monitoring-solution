# Copyright (c) Microsoft. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for
# full license information.

import os
import sys
import time
import asyncio
import logging
import threading
from random import randint
from six.moves import input
from datetime import datetime
from azure.iot.device.aio import IoTHubModuleClient
from CustomLogger import CustomLogger

RANDOM_PHRASES = [
    "Alcohol! Because no great story started with someone eating a salad.",
    "I don't need a hair stylist, my pillow gives me a new hairstyle every morning.",
    "Don't worry if plan A fails, there are 25 more letters in the alphabet.",
    "If I'm not back in five minutes, just wait longer...",
    "A bank is a place that will lend you money, if you can prove that you don't need it.",
    "A balanced diet means a cupcake in each hand.",
    "Doing nothing is hard, you never know when you're done.",
    "If you're not supposed to eat at night, why is there a light bulb in the refrigerator?",
    "Don't drink while driving - you might spill the beer.",
    "I think the worst time to have a heart attack is during a game of charades.",
    "I refuse to answer that question on the grounds that I don't know the answer.",
    "Alcohol doesn't solve any problem, but neither does milk.",
    "Funny saying about drinking alcohol",
    "My wallet is like an onion. When I open it, it makes me cry...",
    "Doesn't expecting the unexpected make the unexpected expected?",
    "I'm not clumsy, The floor just hates me, the table and chairs are bullies and the walls get in my way.",
    "Life is short, smile while you still have teeth.",
    "The only reason I'm fat is because a tiny body couldn't store all this personality.",
    "I'm jealous of my parents, I'll never have a kid as cool as them.",
    "I'm not lazy, I'm just very relaxed.",
    "Always remember you're unique, just like everyone else.",
    "You're born free, then you're taxed to death.",
    "The best part of going to work is coming back home at the end of the day.",
    "A cookie a day keeps the sadness away. An entire jar of cookies a day brings it back.",
    "A successful man is one who makes more money than his wife can spend. A successful woman is one who can find such a man.",
    "I asked God for a bike, but I know God doesn't work that way. So I stole a bike and asked for forgiveness.",
    "Do not argue with an idiot. He will drag you down to his level and beat you with experience.",
    "If you think nobody cares if you're alive, try missing a couple of bank payments.",
    "Money can't buy happiness, but it sure makes misery easier to live with.",
    "If you do a job too well, you'll get stuck with it.",
    "Quantity is what you count, quality is what you count on.",
    "The road to success is always under construction.",
    "When you're right, no one remembers. When you're wrong, no one forgets.",
    "If you can't see the bright side of life, polish the dull side.",
    "If you can't live without me, why aren't you dead yet?",
    "Don't tell me the sky is the limit when there are footprints on the moon.",
    "I don't suffer from insanity, I enjoy every minute of it.",
    "I get enough exercise pushing my luck.",
    "Funny saying about excercising",
    "Sometimes I wake up grumpy; other times I let her sleep.",
    "God created the world, everything else is made in China.",
    "Birthdays are good for you. Statistics show that people who have the most live the longest.",
    "When life gives you melons, you might be dyslexic.",
    "Children in the back seat cause accidents, accidents in the back seat cause children!",
    "I'd like to help you out today. Which way did you come in?",
    "You never truly understand something until you can explain it to your grandmother.",
    "Experience is a wonderful thing. It enables you to recognise a mistake when you make it again.",
    "You can't have everything, where would you put it?",
    "Don't you wish they made a clap on clap off device for some peoples mouths?",
    "If your parents never had children, chances are you won't either.",
]
LOG_LEVELS = [
    logging.DEBUG,
    logging.INFO,
    logging.WARNING,
    logging.ERROR,
    logging.CRITICAL,
]
SLEEP_TIME = int(os.environ.get("SLEEP_TIME", "60"))

# initialize logger
logger = CustomLogger()

async def main():
    try:
        if not sys.version >= "3.5.3":
            raise Exception("The sample requires python 3.5.3+. Current version of Python: %s" % sys.version)
        print("IoT Hub Client for Python")

        # The client object is used to interact with your Azure IoT hub.
        module_client = IoTHubModuleClient.create_from_edge_environment()

        # connect the client.
        await module_client.connect()

        # define behavior for receiving an input message on input1
        async def input1_listener(module_client):
            while True:
                input_message = await module_client.receive_message_on_input("input1")  # blocking call
                print("the data in the message received on input1 was ")
                print(input_message.data)
                print("custom properties are")
                print(input_message.custom_properties)
                print("forwarding mesage to output1")
                await module_client.send_message_to_output(input_message, "output1")

        # define behavior for halting the application
        def stdin_listener():
            while True:
                try:
                    log_level = LOG_LEVELS[randint(0, len(LOG_LEVELS) - 1)]
                    message = RANDOM_PHRASES[randint(0, len(RANDOM_PHRASES) - 1)]
                    logger.log(log_level, message)
                    time.sleep(SLEEP_TIME)
                except Exception as e:
                    logging.exception(e)
                    time.sleep(SLEEP_TIME)

        # Schedule task for C2D Listener
        listeners = asyncio.gather(input1_listener(module_client))

        print ( "The sample is now waiting for messages. ")

        # Run the stdin listener in the event loop
        loop = asyncio.get_event_loop()
        user_finished = loop.run_in_executor(None, stdin_listener)

        # Wait for user to indicate they are done listening for messages
        await user_finished

        # Cancel listening
        listeners.cancel()

        # Finally, disconnect
        await module_client.disconnect()

    except Exception as e:
        print ( "Unexpected error %s " % e )
        raise

if __name__ == "__main__":
    # loop = asyncio.get_event_loop()
    # loop.run_until_complete(main())
    # loop.close()

    # If using Python 3.7 or above, you can use following code instead:
    asyncio.run(main())