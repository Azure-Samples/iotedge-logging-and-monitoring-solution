using FilterModule;
using Microsoft.Azure.Devices.Client;
using Newtonsoft.Json;
using System;
using System.Text;
using Xunit;

namespace FilterModuleUnitTest
{
    public class FilterModuleUnitTest
    {
        [Fact]
        public void FilterLessThanThresholdTest()
        {
            var source = CreateMessage(25 - 1);
            var result = Program.Filter(source);
            Assert.Null(result);
        }

        [Fact]
        public void FilterMoreThanThresholdAlertPropertyTest()
        {
            var source = CreateMessage(25 + 1);
            var result = Program.Filter(source);
            Assert.Equal("Alert", result.Properties["MessageType"]);
        }

        [Fact]
        public void FilterMoreThanThresholdCopyPropertyTest()
        {
            const string expected = "customTestValue";
            var source = CreateMessage(25 + 1);
            source.Properties.Add("customTestKey", expected);

            var result = Program.Filter(source);

            Assert.Equal(expected, result.Properties["customTestKey"]);
        }

        private Message CreateMessage(int temperature)
        {
            var messageBody = CreateMessageBody(temperature);
            var messageString = JsonConvert.SerializeObject(messageBody);
            var messageBytes = Encoding.UTF8.GetBytes(messageString);

            return new Message(messageBytes)
            {
                ContentType = "application/json",
                ContentEncoding = "utc-8",
            };
        }

        private MessageBody CreateMessageBody(int temperature)
        {
            var messageBody = new MessageBody
            {
                machine = new Machine
                {
                    temperature = temperature,
                    pressure = 0
                },
                ambient = new Ambient
                {
                    temperature = 0,
                    humidity = 0
                },
                timeCreated = DateTime.UtcNow.ToString("O"),
            };

            return messageBody;
        }
    }
}