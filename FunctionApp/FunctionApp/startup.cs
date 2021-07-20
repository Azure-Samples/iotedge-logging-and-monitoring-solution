using System;
using FunctionApp.CertificateGenerator;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Azure.Functions.Extensions.DependencyInjection;

[assembly: FunctionsStartup(typeof(FunctionApp.Startup))]
namespace FunctionApp
{
    public class Startup : FunctionsStartup
    {
        public IConfiguration Configuration { get; }

        public override void Configure(IFunctionsHostBuilder builder)
        {
            try
            {
                builder.Services
                    .AddLogging()
                    .AddHttpClient()
                    .AddSingleton<CertGenerator, CertGenerator>()
                    .AddSingleton<AzureLogAnalytics, AzureLogAnalytics>();
            }
            catch (Exception e)
            {
                throw e;
            }
        }
    }
}
