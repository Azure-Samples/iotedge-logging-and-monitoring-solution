namespace CsharpSampleModule
{
    using System;
    using System.Linq;
    using System.Text;
    using System.Timers;
    using System.Threading;
    using System.Threading.Tasks;
    using System.Collections.Generic;
    using System.Runtime.Loader;
    using Microsoft.Extensions.Logging;
    using Microsoft.Azure.Devices.Client;
    using Microsoft.Azure.Devices.Client.Transport.Mqtt;
    using IoTEdgeLogger;
    
    class Program
    {
        static int _counter;
        static ILogger _log;
        static System.Timers.Timer _eventTimer;
        static List<string> _randomPhrases = new List<string>()
        {
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
        };

        static void Main(string[] args)
        {
            Logger.SetLogLevel("debug");
            _log = Logger.Factory.CreateLogger<string>();

            // Set timer
            int _sleepTime = Convert.ToInt32(Environment.GetEnvironmentVariable("SLEEP_TIME"));
            SetTimer(_sleepTime * 1000);

            // To run on IoT Edge
            Init().Wait();
            // To debug locally
            //EndlessLoop();

            
            // Wait until the app unloads or is cancelled
            var cts = new CancellationTokenSource();
            AssemblyLoadContext.Default.Unloading += (ctx) => cts.Cancel();
            Console.CancelKeyPress += (sender, cpe) => cts.Cancel();
            WhenCancelled(cts.Token).Wait();
        }

        /// <summary>
        /// Handles cleanup operations when app is cancelled or unloads
        /// </summary>
        public static Task WhenCancelled(CancellationToken cancellationToken)
        {
            var tcs = new TaskCompletionSource<bool>();
            cancellationToken.Register(s => ((TaskCompletionSource<bool>)s).SetResult(true), tcs);
            return tcs.Task;
        }

        /// <summary>
        /// Initializes the ModuleClient and sets up the callback to receive
        /// messages containing temperature information
        /// </summary>
        static async Task Init()
        {
            MqttTransportSettings mqttSetting = new MqttTransportSettings(TransportType.Mqtt_Tcp_Only);
            ITransportSettings[] settings = { mqttSetting };

            // Open a connection to the Edge runtime
            ModuleClient ioTHubModuleClient = await ModuleClient.CreateFromEnvironmentAsync(settings);
            await ioTHubModuleClient.OpenAsync();
            Console.WriteLine("IoT Hub module client initialized.");

            // Register callback to be called when a message is received by the module
            await ioTHubModuleClient.SetInputMessageHandlerAsync("input1", PipeMessage, ioTHubModuleClient);
        }

        /// <summary>
        /// Endless loop used for local debugging
        /// </summary>
        static void EndlessLoop()
        {
            while (true) { }
        }

        /// <summary>
        /// This method is called whenever the module is sent a message from the EdgeHub. 
        /// It just pipe the messages without any change.
        /// It prints all the incoming messages.
        /// </summary>
        static async Task<MessageResponse> PipeMessage(Message message, object userContext)
        {
            int counterValue = Interlocked.Increment(ref _counter);

            var moduleClient = userContext as ModuleClient;
            if (moduleClient == null)
            {
                throw new InvalidOperationException("UserContext doesn't contain " + "expected values");
            }

            byte[] messageBytes = message.GetBytes();
            string messageString = Encoding.UTF8.GetString(messageBytes);
            Console.WriteLine($"Received message: {counterValue}, Body: [{messageString}]");

            if (!string.IsNullOrEmpty(messageString))
            {
                using (var pipeMessage = new Message(messageBytes))
                {
                    foreach (var prop in message.Properties)
                    {
                        pipeMessage.Properties.Add(prop.Key, prop.Value);
                    }
                    await moduleClient.SendEventAsync("output1", pipeMessage);
                
                    Console.WriteLine("Received message sent");
                }
            }
            return MessageResponse.Completed;
        }

        static void SetTimer(int timerDelay)
        {
            try
            {
                _log.LogInformation("Setting timer with {0} delay", timerDelay);

                _eventTimer = new System.Timers.Timer(timerDelay);
                _eventTimer.Elapsed += (sender, e) => OnTimedEvent(sender, e);
                _eventTimer.AutoReset = true;
                _eventTimer.Enabled = true;
            }
            catch (Exception e)
            {
                _log.LogError($"SetTimer caught an exception: {e}");
            }
        }

        /// <summary>
        /// Callback method to be executed every time the timer resets.
        /// </summary>
        private static void OnTimedEvent(Object source, ElapsedEventArgs e)
        {
            try
            {
                WriteLog();
            }
            catch (Exception ex)
            {
                _log.LogError($"OnTimedEvent caught an exception: {ex}");
            }
        }

        /// <summary>
        /// This method uses the provided console logger instance to write logs.
        /// </summary>
        private static void WriteLog()
        {
            var random = new Random();
            var logMessage = _randomPhrases[random.Next(_randomPhrases.Count)];
            var logLevels = Logger.LogLevelDictionary.Keys.ToArray();
            var logLevel = Logger.LogLevelDictionary[logLevels[random.Next(logLevels.Length)]];

            _log.Log((LogLevel)logLevel, logMessage);
        }
    }
}
