package net.kroia.stockmarketbridge;

import dan200.computercraft.api.lua.IArguments;
import dan200.computercraft.api.lua.LuaException;
import dan200.computercraft.api.lua.LuaFunction;
import dan200.computercraft.api.peripheral.IPeripheral;
import net.kroia.banksystem.banking.BankUser;
import net.kroia.banksystem.banking.ServerBankManager;
import net.kroia.banksystem.banking.bank.Bank;
import net.kroia.stockmarket.market.server.ServerMarket;
import net.kroia.stockmarket.market.server.ServerTradeItem;
import net.kroia.stockmarket.market.server.order.LimitOrder;
import net.kroia.stockmarket.market.server.order.MarketOrder;
import net.kroia.stockmarket.market.server.order.Order;
import net.kroia.stockmarket.util.OrderbookVolume;
import net.kroia.stockmarket.util.PriceHistory;
import org.jetbrains.annotations.Nullable;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;

/**
 * Périphérique Lua "trading_bridge".
 *
 * Toutes les méthodes s'exécutent sur le thread serveur (mainThread = true) car elles
 * touchent aux structures du marché et de la banque, qui ne sont pas thread-safe.
 * Les ordres sont passés sans joueur en ligne : ils sont marqués "bot" par StockMarket
 * (cf. {@link Order#isBot()}), donc exécutés même si le marché est fermé aux joueurs.
 */
public class TradingBridgePeripheral implements IPeripheral {
    private static final int MAX_HISTORY = 1000;
    private static final int MAX_TILES = 1000;

    private final TradingBridgeBlockEntity be;

    public TradingBridgePeripheral(TradingBridgeBlockEntity be) {
        this.be = be;
    }

    @Override
    public String getType() {
        return "trading_bridge";
    }

    @Nullable
    @Override
    public Object getTarget() {
        return be;
    }

    @Override
    public boolean equals(@Nullable IPeripheral other) {
        return other instanceof TradingBridgePeripheral p && p.be == be;
    }

    // ------------------------------------------------------------------ helpers

    private BankUser user() throws LuaException {
        UUID id = be.getOwnerUUID();
        if (id == null) {
            throw new LuaException("Pont non lié : il doit être posé par un joueur");
        }
        BankUser user = ServerBankManager.getUser(id);
        if (user == null) {
            throw new LuaException("Le joueur lié (" + be.getOwnerName() + ") n'a pas de compte BankSystem");
        }
        return user;
    }

    private static String market(IArguments args, int index) throws LuaException {
        String item = args.getString(index);
        if (!ServerMarket.hasItem(item)) {
            throw new LuaException("Aucun marché pour l'item : " + item);
        }
        return item;
    }

    private static Bank itemBank(BankUser user, String item) throws LuaException {
        Bank bank = user.getBank(item);
        if (bank == null) {
            bank = user.createItemBank_noMSG_Feedback(item, 0);
        }
        if (bank == null) {
            throw new LuaException("Item non autorisé dans BankSystem : " + item);
        }
        return bank;
    }

    private static Bank moneyBank(BankUser user) throws LuaException {
        Bank bank = user.getMoneyBank();
        if (bank == null) {
            throw new LuaException("Le joueur lié n'a pas de compte d'argent");
        }
        return bank;
    }

    private static Map<String, Object> balanceMap(@Nullable Bank bank) {
        Map<String, Object> m = new HashMap<>();
        m.put("available", bank == null ? 0L : bank.getBalance());
        m.put("locked", bank == null ? 0L : bank.getLockedBalance());
        return m;
    }

    private static Map<String, Object> orderMap(Order o) {
        Map<String, Object> m = new HashMap<>();
        m.put("id", o.getOrderID());
        m.put("item", o.getItemID());
        m.put("amount", o.getAmount());
        m.put("filled", o.getFilledAmount());
        m.put("status", o.getStatus().name().toLowerCase(Locale.ROOT));
        m.put("averagePrice", o.getAveragePrice());
        m.put("transferredMoney", o.getTransferedMoney());
        if (o instanceof LimitOrder limit) {
            m.put("type", "limit");
            m.put("price", limit.getPrice());
        } else {
            m.put("type", "market");
        }
        return m;
    }

    // ------------------------------------------------------------------ compte lié

    /** Nom du joueur auquel le pont est lié ("" si non lié). */
    @LuaFunction(mainThread = true)
    public final String getOwner() {
        return be.getOwnerName();
    }

    // ------------------------------------------------------------------ marchés

    @LuaFunction(mainThread = true)
    public final List<Map<String, Object>> getMarkets() {
        List<Map<String, Object>> out = new ArrayList<>();
        for (ServerTradeItem item : ServerMarket.getTradeItems().values()) {
            Map<String, Object> m = new HashMap<>();
            m.put("item", item.getItemID());
            m.put("price", item.getPrice());
            m.put("open", item.isMarketOpen());
            out.add(m);
        }
        return out;
    }

    @LuaFunction(mainThread = true)
    public final boolean hasMarket(String item) {
        return ServerMarket.hasItem(item);
    }

    @LuaFunction(mainThread = true)
    public final int getPrice(IArguments args) throws LuaException {
        return ServerMarket.getPrice(market(args, 0));
    }

    @LuaFunction(mainThread = true)
    public final boolean isMarketOpen(IArguments args) throws LuaException {
        return ServerMarket.isMarketOpen(market(args, 0));
    }

    /** getPriceHistory(item, [n]) : les n dernières bougies, de la plus ancienne à la plus récente. */
    @LuaFunction(mainThread = true)
    public final List<Map<String, Object>> getPriceHistory(IArguments args) throws LuaException {
        String item = market(args, 0);
        int n = args.optInt(1, 50);
        if (n < 1) throw new LuaException("n doit être >= 1");
        PriceHistory history = ServerMarket.getPriceHistory(item);
        List<Map<String, Object>> out = new ArrayList<>();
        if (history == null) return out;
        int size = history.size();
        int count = Math.min(Math.min(n, MAX_HISTORY), size);
        for (int i = size - count; i < size; i++) {
            Map<String, Object> m = new HashMap<>();
            m.put("time", history.getTimeStamp(i).getTimeStamp());
            m.put("open", history.getOpenPrice(i));
            m.put("high", history.getHighPrice(i));
            m.put("low", history.getLowPrice(i));
            m.put("close", history.getClosePrice(i));
            out.add(m);
        }
        return out;
    }

    /** getOrderBook(item, tiles, [minPrice], [maxPrice]) : profondeur du carnet d'ordres. */
    @LuaFunction(mainThread = true)
    public final Map<String, Object> getOrderBook(IArguments args) throws LuaException {
        String item = market(args, 0);
        int tiles = args.getInt(1);
        if (tiles < 1 || tiles > MAX_TILES) {
            throw new LuaException("tiles doit être entre 1 et " + MAX_TILES);
        }
        int price = ServerMarket.getPrice(item);
        int min = args.optInt(2, Math.max(0, price - Math.max(1, price / 2)));
        int max = args.optInt(3, price + Math.max(1, price / 2));
        if (min < 0) min = 0;
        if (max <= min) throw new LuaException("maxPrice doit être > minPrice");
        if (max - min < tiles) tiles = max - min;

        OrderbookVolume vol = ServerMarket.getOrderBookVolume(item, tiles, min, max);
        if (vol == null) throw new LuaException("Carnet d'ordres indisponible pour " + item);

        List<Integer> volume = new ArrayList<>(vol.getTiles());
        for (int i = 0; i < vol.getTiles(); i++) volume.add(vol.getVolume(i));

        Map<String, Object> m = new HashMap<>();
        m.put("minPrice", vol.getMinPrice());
        m.put("maxPrice", vol.getMaxPrice());
        m.put("tiles", vol.getTiles());
        m.put("volume", volume);
        return m;
    }

    // ------------------------------------------------------------------ soldes

    @LuaFunction(mainThread = true)
    public final Map<String, Object> getBalance() throws LuaException {
        return balanceMap(moneyBank(user()));
    }

    @LuaFunction(mainThread = true)
    public final Map<String, Object> getItemBalance(IArguments args) throws LuaException {
        String item = args.getString(0);
        return balanceMap(user().getBank(item));
    }

    // ------------------------------------------------------------------ ordres

    /** buy(item, amount) : ordre au marché, achat. false si fonds insuffisants ou ordre invalide. */
    @LuaFunction(mainThread = true)
    public final boolean buy(IArguments args) throws LuaException {
        String item = market(args, 0);
        int amount = args.getInt(1);
        if (amount <= 0) throw new LuaException("amount doit être > 0");
        return placeMarket(item, amount);
    }

    /** sell(item, amount) : ordre au marché, vente. false si items insuffisants ou ordre invalide. */
    @LuaFunction(mainThread = true)
    public final boolean sell(IArguments args) throws LuaException {
        String item = market(args, 0);
        int amount = args.getInt(1);
        if (amount <= 0) throw new LuaException("amount doit être > 0");
        return placeMarket(item, -amount);
    }

    private boolean placeMarket(String item, int signedAmount) throws LuaException {
        BankUser user = user();
        MarketOrder order = MarketOrder.createBotOrder(
                user.getPlayerUUID(), moneyBank(user), itemBank(user, item), item, signedAmount);
        if (order == null) return false;
        ServerMarket.addOrder(order);
        return order.getStatus() != Order.Status.INVALID;
    }

    /** placeLimitOrder(item, amount, price) : amount > 0 achat, < 0 vente. Renvoie l'ID de l'ordre. */
    @LuaFunction(mainThread = true)
    public final long placeLimitOrder(IArguments args) throws LuaException {
        String item = market(args, 0);
        int amount = args.getInt(1);
        int price = args.getInt(2);
        if (amount == 0) throw new LuaException("amount ne peut pas être 0");
        if (price <= 0) throw new LuaException("price doit être > 0");

        BankUser user = user();
        LimitOrder order = LimitOrder.createBotOrder(
                user.getPlayerUUID(), moneyBank(user), itemBank(user, item), item, amount, price);
        if (order == null) {
            throw new LuaException(amount > 0
                    ? "Fonds insuffisants pour acheter " + amount + " x " + item + " à " + price
                    : "Items insuffisants pour vendre " + (-amount) + " x " + item);
        }
        ServerMarket.addOrder(order);
        if (order.getStatus() == Order.Status.INVALID) {
            throw new LuaException("Ordre invalide : " + order.getInvalidReason());
        }
        return order.getOrderID();
    }

    /** getOrders([item]) : ordres en attente du joueur lié. */
    @LuaFunction(mainThread = true)
    public final List<Map<String, Object>> getOrders(IArguments args) throws LuaException {
        BankUser user = user();
        List<Order> orders = args.count() > 0 && args.get(0) != null
                ? ServerMarket.getOrders(args.getString(0), user.getPlayerUUID())
                : ServerMarket.getOrdersFromUser(user.getPlayerUUID());
        List<Map<String, Object>> out = new ArrayList<>();
        for (Order o : orders) out.add(orderMap(o));
        return out;
    }

    /** cancelOrder(orderID) : annule un ordre en attente du joueur lié. false s'il n'existe pas. */
    @LuaFunction(mainThread = true)
    public final boolean cancelOrder(IArguments args) throws LuaException {
        long id = args.getLong(0);
        BankUser user = user();
        // On ne laisse annuler que les ordres du joueur lié.
        boolean mine = false;
        for (Order o : ServerMarket.getOrdersFromUser(user.getPlayerUUID())) {
            if (o.getOrderID() == id) {
                mine = true;
                break;
            }
        }
        if (!mine) return false;
        ServerMarket.cancelOrder(id);
        return true;
    }
}
