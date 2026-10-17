import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;

import java.io.IOException;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.Executors;
import java.util.concurrent.ThreadLocalRandom;
import java.util.logging.Logger;

/**
 * Inventory service. Plain JDK, no frameworks.
 *
 * Exposes GET /stock/{sku}. Backed by an in-memory "database" that is
 * deliberately a bit noisy in its logs (cache misses), to give investigators
 * something to look at that is NOT the problem.
 */
public class Inventory {
    private static final Logger LOG = Logger.getLogger("inventory");
    private static final Map<String, Integer> STOCK = new ConcurrentHashMap<>(Map.of(
            "US-TSHIRT-01", 120,
            "US-MUG-02", 45,
            "EU-HOODIE-03", 30,
            "EU-POSTER-04", 200
    ));
    private static final Map<String, Integer> CACHE = new ConcurrentHashMap<>();

    public static void main(String[] args) throws IOException {
        int port = Integer.parseInt(System.getenv().getOrDefault("PORT", "8081"));
        HttpServer server = HttpServer.create(new InetSocketAddress(port), 0);
        server.setExecutor(Executors.newFixedThreadPool(8));
        server.createContext("/healthz", ex -> respond(ex, 200, "{\"status\":\"ok\"}"));
        server.createContext("/stock/", Inventory::handleStock);
        server.start();
        LOG.info("inventory listening on :" + port);
    }

    private static void handleStock(HttpExchange ex) throws IOException {
        String sku = ex.getRequestURI().getPath().substring("/stock/".length());
        Integer available = CACHE.get(sku);
        if (available == null) {
            LOG.info("cache miss for sku=" + sku + ", querying stock table");
            sleep(ThreadLocalRandom.current().nextInt(10, 40));
            available = STOCK.get(sku);
            if (available == null) {
                LOG.warning("unknown sku=" + sku);
                respond(ex, 404, "{\"error\":\"unknown sku\"}");
                return;
            }
            CACHE.put(sku, available);
        } else {
            sleep(ThreadLocalRandom.current().nextInt(1, 5));
        }
        // Simulate stock drifting over time so it never hits zero in the workshop.
        int shown = Math.max(5, available - ThreadLocalRandom.current().nextInt(0, 5));
        respond(ex, 200, String.format("{\"sku\":\"%s\",\"available\":%d}", sku, shown));
    }

    private static void respond(HttpExchange ex, int status, String body) throws IOException {
        byte[] bytes = body.getBytes(StandardCharsets.UTF_8);
        ex.getResponseHeaders().add("Content-Type", "application/json");
        ex.sendResponseHeaders(status, bytes.length);
        try (OutputStream os = ex.getResponseBody()) {
            os.write(bytes);
        }
    }

    private static void sleep(long ms) {
        try {
            Thread.sleep(ms);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }
}
