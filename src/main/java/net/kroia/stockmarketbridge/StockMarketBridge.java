package net.kroia.stockmarketbridge;

import net.minecraft.world.item.CreativeModeTabs;
import net.minecraftforge.event.BuildCreativeModeTabContentsEvent;
import net.minecraftforge.eventbus.api.IEventBus;
import net.minecraftforge.fml.common.Mod;
import net.minecraftforge.fml.javafmlmod.FMLJavaModLoadingContext;

/**
 * Pont entre StockMarket (KROIA) et CC: Tweaked.
 */
@Mod(StockMarketBridge.MOD_ID)
public class StockMarketBridge {
    public static final String MOD_ID = "stockmarketbridge";

    public StockMarketBridge() {
        IEventBus modBus = FMLJavaModLoadingContext.get().getModEventBus();
        BridgeRegistry.register(modBus);
        modBus.addListener(StockMarketBridge::addCreative);
    }

    private static void addCreative(BuildCreativeModeTabContentsEvent event) {
        if (event.getTabKey() == CreativeModeTabs.REDSTONE_BLOCKS) {
            event.accept(BridgeRegistry.TRADING_BRIDGE_ITEM);
        }
    }
}
