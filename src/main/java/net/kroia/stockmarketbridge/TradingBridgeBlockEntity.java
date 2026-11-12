package net.kroia.stockmarketbridge;

import dan200.computercraft.api.peripheral.IPeripheral;
import net.minecraft.core.BlockPos;
import net.minecraft.core.Direction;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.world.level.block.entity.BlockEntity;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraftforge.common.capabilities.Capability;
import net.minecraftforge.common.capabilities.CapabilityManager;
import net.minecraftforge.common.capabilities.CapabilityToken;
import net.minecraftforge.common.util.LazyOptional;
import org.jetbrains.annotations.NotNull;
import org.jetbrains.annotations.Nullable;

import java.util.UUID;

public class TradingBridgeBlockEntity extends BlockEntity {
    /** Même token que celui utilisé par CC: Tweaked (cf. son mod d'exemple Forge). */
    public static final Capability<IPeripheral> CAPABILITY_PERIPHERAL =
            CapabilityManager.get(new CapabilityToken<>() {});

    private UUID ownerUUID;
    private String ownerName = "";
    private LazyOptional<IPeripheral> peripheral;

    public TradingBridgeBlockEntity(BlockPos pos, BlockState state) {
        super(BridgeRegistry.TRADING_BRIDGE_BE.get(), pos, state);
    }

    public boolean hasOwner() {
        return ownerUUID != null;
    }

    @Nullable
    public UUID getOwnerUUID() {
        return ownerUUID;
    }

    public String getOwnerName() {
        return ownerName;
    }

    public void setOwner(UUID uuid, String name) {
        this.ownerUUID = uuid;
        this.ownerName = name == null ? "" : name;
        setChanged();
    }

    @NotNull
    @Override
    public <T> LazyOptional<T> getCapability(@NotNull Capability<T> cap, @Nullable Direction side) {
        if (cap == CAPABILITY_PERIPHERAL && !isRemoved()) {
            if (peripheral == null) {
                peripheral = LazyOptional.of(() -> new TradingBridgePeripheral(this));
            }
            return peripheral.cast();
        }
        return super.getCapability(cap, side);
    }

    @Override
    public void invalidateCaps() {
        super.invalidateCaps();
        if (peripheral != null) {
            peripheral.invalidate();
            peripheral = null;
        }
    }

    @Override
    protected void saveAdditional(@NotNull CompoundTag tag) {
        super.saveAdditional(tag);
        if (ownerUUID != null) {
            tag.putUUID("OwnerUUID", ownerUUID);
            tag.putString("OwnerName", ownerName);
        }
    }

    @Override
    public void load(@NotNull CompoundTag tag) {
        super.load(tag);
        if (tag.hasUUID("OwnerUUID")) {
            ownerUUID = tag.getUUID("OwnerUUID");
            ownerName = tag.getString("OwnerName");
        } else {
            ownerUUID = null;
            ownerName = "";
        }
    }
}
