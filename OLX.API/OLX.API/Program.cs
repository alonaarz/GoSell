using Olx.BLL.Exstensions;
using Olx.BLL.Hubs;
using Olx.DAL.Exstension;
using OLX.API.Extensions;
using OLX.API.Middlewares;

var builder = WebApplication.CreateBuilder(args);

// ================= SERVICES =================
builder.Services.AddOlxDbContext(builder.Configuration);
builder.Services.AddOlxBLLServices(builder.Configuration);
builder.Services.AddOlxApiConfigurations(builder.Configuration);

builder.Services.AddControllers();

builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

builder.Services.AddSignalR();

builder.Logging.ClearProviders();
builder.Logging.AddConsole();

var app = builder.Build();

// ================= MIDDLEWARE PIPELINE =================

// ❗ Глобальний error handler має бути ПЕРШИМ
app.UseMiddleware<GlobalExceptionHandlerMiddleware>();

// ❗ Swagger тільки в development (щоб не ламати production/Docker)
if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

// ❗ Статика (якщо є)
app.AddStaticFiles();

// ❗ Routing ОБОВʼЯЗКОВИЙ (часта причина багів)
app.UseRouting();

// ❗ CORS після routing
app.UseCors("AllowOrigins");

// ❗ Auth pipeline
app.UseAuthentication();
app.UseAuthorization();

// ❗ HTTPS (якщо Docker/Nginx дає проблеми — можна потім вимкнути)
app.UseHttpsRedirection();

// ❗ Максимальний body size (якщо ти це використовуєш)
app.SetMaxRequestBodySize();

// ================= ENDPOINTS =================

app.MapControllers();
app.MapHub<MessageHub>("/hub");

// ================= DB INIT =================

// ⚠️ Міграції та seed — обережно, але залишаємо як ти хотіла
try
{
    app.DataBaseMigrate();
    await app.SeedDataAsync();
}
catch (Exception ex)
{
    // щоб контейнер НЕ падав повністю
    Console.WriteLine($"DB init error: {ex.Message}");
}

// ================= RUN =================
await app.RunAsync();
